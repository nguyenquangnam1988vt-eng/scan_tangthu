import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/session.dart';

/// Advanced document PDF service.
///
/// Pipeline:
///   1) EXIF orientation
///   2) OpenCV decode / resize
///   3) document contour detection
///   4) perspective correction
///   5) document enhancement
///      - bilateral denoise
///      - CLAHE for grayscale/BW
///      - local background normalization via division
///      - adaptive threshold
///      - morphology cleanup
///      - controlled unsharp mask
///   6) JPEG encode
///   7) A4 PDF
class PdfService {
  static Future<File> createPdf({
    required List<String> imagePaths,
    required String outputPath,
    required ScanMode mode,
    int jpegQuality = 93,
    int maxWidth = 2200,
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('imagePaths không được rỗng.');
    }
    if (outputPath.trim().isEmpty) {
      throw ArgumentError('outputPath không hợp lệ.');
    }

    final quality = jpegQuality.clamp(88, 97);
    final width = maxWidth.clamp(1600, 2600);

    final jpgBytesList = await compute(
      _processImages,
      _ProcessArgs(
        paths: imagePaths,
        mode: mode.index,
        jpegQuality: quality,
        maxWidth: width,
      ),
    );

    if (jpgBytesList.isEmpty) {
      throw Exception('Không có ảnh hợp lệ để tạo PDF.');
    }

    final doc = pw.Document(compress: true);

    for (final jpg in jpgBytesList) {
      if (jpg.isEmpty) continue;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(4),
          build: (_) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(jpg),
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
      );
    }

    final file = File(outputPath);
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static Future<List<Uint8List>> _processImages(_ProcessArgs args) async {
    final mode = ScanMode.values[args.mode];
    final result = <Uint8List>[];

    for (final path in args.paths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        // OpenCV does not apply JPEG EXIF orientation for imdecode().
        final orientedBytes = _normalizeExifOrientation(bytes);

        Uint8List? processed;

        // Primary path: OpenCV document scanner.
        try {
          processed = _processWithOpenCv(
            orientedBytes,
            mode,
            args.maxWidth,
            args.jpegQuality,
          );
        } catch (_) {
          processed = null;
        }

        // Safe fallback: pure-Dart pipeline.
        processed ??= _processWithDartFallback(
          orientedBytes,
          mode,
          args.maxWidth,
          args.jpegQuality,
        );

        if (processed != null && processed.isNotEmpty) {
          result.add(processed);
        }
      } catch (_) {
        // One corrupt image must not kill the whole PDF.
        continue;
      }
    }

    return result;
  }

  // ==========================================================================
  // OPEN CV PIPELINE
  // ==========================================================================

  static Uint8List _processWithOpenCv(
    Uint8List bytes,
    ScanMode mode,
    int maxWidth,
    int jpegQuality,
  ) {
    cv.Mat? src;
    cv.Mat? work;
    cv.Mat? corrected;

    try {
      src = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (src.empty) {
        throw StateError('OpenCV không decode được ảnh.');
      }

      work = src;

      // Do the expensive contour search on a much smaller image.
      // The full-resolution image is retained for final warp.
      if (work.cols > maxWidth) {
        final scale = maxWidth / work.cols;
        work = cv.resize(
          work,
          (maxWidth, (work.rows * scale).round()),
          interpolation: cv.INTER_AREA,
        );
      }

      // Cap contour-search image at ~960 px for older iPhones.
      final detection = _detectDocumentAndWarp(
        work,
        maxDetectionWidth: 960,
      );

      corrected = detection ?? work;

      // Enhance after perspective correction.
      final beforeEnhance = corrected;
      corrected = _enhanceOpenCv(corrected, mode);
      if (!identical(corrected, beforeEnhance)) {
        _safeDispose(beforeEnhance);
      }

      return _encodeJpeg(corrected, jpegQuality);
    } finally {
      // Dispose corrected first, but avoid double-dispose.
      if (corrected != null && !identical(corrected, src)) {
        _safeDispose(corrected);
      }
      if (work != null &&
          !identical(work, src) &&
          !identical(work, corrected)) {
        _safeDispose(work);
      }
      _safeDispose(src);
    }
  }

  /// Detect the largest convincing 4-corner document contour.
  static cv.Mat? _detectDocumentAndWarp(
    cv.Mat src, {
    int maxDetectionWidth = 1200,
  }) {
    cv.Mat? small;
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? edges;
    cv.Mat? closed;
    cv.Mat? kernel;
    cv.Mat? warped;

    cv.Contours? contours;
    cv.VecVec4i? hierarchy;

    cv.VecPoint? source;
    cv.VecPoint? destination;
    cv.Mat? transform;

    try {
      small = src;
      double sx = 1.0;
      double sy = 1.0;

      if (src.cols > maxDetectionWidth) {
        sx = maxDetectionWidth / src.cols;
        sy = sx;
        small = cv.resize(
          src,
          (maxDetectionWidth, (src.rows * sy).round()),
          interpolation: cv.INTER_AREA,
        );
      }

      gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);

      // Canny thresholds are moderate: document borders can be weak
      // when the paper is white on a pale table.
      edges = cv.canny(blurred, 45, 140, l2gradient: true);

      // Close small breaks in paper edges.
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      closed = cv.morphologyEx(
        edges,
        cv.MORPH_CLOSE,
        kernel,
        iterations: 2,
      );

      final result = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      contours = result.$1;
      hierarchy = result.$2;

      if (contours.isEmpty) return null;

      final imageArea = small.cols * small.rows.toDouble();
      final candidates = <_QuadCandidate>[];

      for (final contour in contours) {
        final area = cv.contourArea(contour).abs();
        if (area < imageArea * 0.12) continue;

        final perimeter = cv.arcLength(contour, true);
        if (perimeter <= 0) continue;

        // Try several approximation strengths.
        cv.VecPoint? bestApprox;
        for (final epsRatio in <double>[0.012, 0.018, 0.025, 0.035]) {
          final approx = cv.approxPolyDP(
            contour,
            perimeter * epsRatio,
            true,
          );
          if (approx.length == 4) {
            bestApprox = approx;
            break;
          }
          _safeDispose(approx);
        }

        if (bestApprox == null) continue;

        try {
          final points = bestApprox.toList();
          if (points.length != 4) continue;

          final ordered = _orderQuad(points);
          final rectangleScore = _rectangleScore(ordered);
          final areaRatio = area / imageArea;

          if (rectangleScore < 0.50) continue;
          if (areaRatio < 0.12) continue;

          final borderBonus = _borderCoverageBonus(
            ordered,
            small.cols,
            small.rows,
          );
          final score = areaRatio * 0.62 +
              rectangleScore * 0.28 +
              borderBonus * 0.10;

          candidates.add(
            _QuadCandidate(
              points: ordered,
              score: score,
              areaRatio: areaRatio,
            ),
          );
        } finally {
          _safeDispose(bestApprox);
        }
      }

      if (candidates.isEmpty) return null;

      candidates.sort((a, b) => b.score.compareTo(a.score));
      final selected = candidates.first;

      // Scale points back to src dimensions.
      final srcPoints = selected.points
          .map(
            (p) => cv.Point(
              (p.x / sx).round(),
              (p.y / sy).round(),
            ),
          )
          .toList();

      final widthTop = _distance(srcPoints[0], srcPoints[1]);
      final widthBottom = _distance(srcPoints[3], srcPoints[2]);
      final heightLeft = _distance(srcPoints[0], srcPoints[3]);
      final heightRight = _distance(srcPoints[1], srcPoints[2]);

      var outWidth = math.max(widthTop, widthBottom).round();
      var outHeight = math.max(heightLeft, heightRight).round();

      if (outWidth < 300 || outHeight < 300) return null;

      // Avoid creating massive mats due to noisy contour geometry.
      const maxOutputSide = 2600;
      final maxSide = math.max(outWidth, outHeight);
      if (maxSide > maxOutputSide) {
        final scale = maxOutputSide / maxSide;
        outWidth = (outWidth * scale).round();
        outHeight = (outHeight * scale).round();
      }

      destination = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(outWidth - 1, 0),
        cv.Point(outWidth - 1, outHeight - 1),
        cv.Point(0, outHeight - 1),
      ]);

      source = cv.VecPoint.fromList(srcPoints);
      transform = cv.getPerspectiveTransform(source, destination);

      warped = cv.warpPerspective(
        src,
        transform,
        (outWidth, outHeight),
        flags: cv.INTER_CUBIC,
        borderMode: cv.BORDER_REPLICATE,
      );

      return warped;
    } finally {
      _safeDispose(transform);
      _safeDispose(source);
      _safeDispose(destination);
      _safeDispose(contours);
      _safeDispose(hierarchy);
      if (!identical(small, src)) _safeDispose(small);
      _safeDispose(gray);
      _safeDispose(blurred);
      _safeDispose(edges);
      _safeDispose(closed);
      _safeDispose(kernel);
      // Do not dispose warped — returned to caller.
    }
  }

  // ==========================================================================
  // OPENCV ENHANCEMENT
  // ==========================================================================

  static cv.Mat _enhanceOpenCv(cv.Mat src, ScanMode mode) {
    switch (mode) {
      case ScanMode.color:
        return _enhanceColor(src);
      case ScanMode.grayscale:
        return _enhanceGrayscale(src);
      case ScanMode.bw:
        return _enhanceBlackWhite(src);
    }
  }

  static cv.Mat _enhanceColor(cv.Mat src) {
    cv.Mat? denoised;
    cv.Mat? adjusted;
    cv.Mat? blur;
    cv.Mat? sharpen;

    try {
      // Bilateral keeps document edges while reducing camera noise.
      denoised = cv.bilateralFilter(src, 5, 35, 35);

      // Gentle contrast/brightness correction.
      adjusted = cv.convertScaleAbs(denoised, alpha: 1.06, beta: 2);

      // Controlled unsharp mask.
      blur = cv.gaussianBlur(adjusted, (0, 0), 1.1);
      sharpen = cv.addWeighted(adjusted, 1.25, blur, -0.25, 0);

      return sharpen;
    } finally {
      _safeDispose(denoised);
      _safeDispose(adjusted);
      _safeDispose(blur);
      // sharpen intentionally returned.
    }
  }

  static cv.Mat _enhanceGrayscale(cv.Mat src) {
    cv.Mat? gray;
    cv.Mat? denoised;
    cv.Mat? claheOut;
    cv.Mat? localBackground;
    cv.Mat? normalized;
    cv.Mat? blur;
    cv.Mat? sharpen;
    cv.CLAHE? clahe;

    try {
      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      denoised = cv.bilateralFilter(gray, 5, 30, 30);

      // CLAHE for local contrast.
      clahe = cv.createCLAHE(clipLimit: 1.8, tileGridSize: (8, 8));
      claheOut = clahe.apply(denoised);

      // Illumination correction via local background division.
      localBackground = cv.gaussianBlur(claheOut, (0, 0), 19);
      normalized = _illuminationNormalize(claheOut, localBackground);

      blur = cv.gaussianBlur(normalized, (0, 0), 1.0);
      sharpen = cv.addWeighted(normalized, 1.24, blur, -0.24, 0);

      return sharpen;
    } finally {
      _safeDispose(clahe);
      _safeDispose(gray);
      _safeDispose(denoised);
      _safeDispose(claheOut);
      _safeDispose(localBackground);
      _safeDispose(normalized);
      _safeDispose(blur);
      // sharpen intentionally returned.
    }
  }

  static cv.Mat _enhanceBlackWhite(cv.Mat src) {
    cv.Mat? gray;
    cv.Mat? denoised;
    cv.Mat? claheOut;
    cv.Mat? background;
    cv.Mat? normalized;
    cv.Mat? binary;
    cv.Mat? clean;
    cv.Mat? kernelClose;
    cv.CLAHE? clahe;

    try {
      gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      denoised = cv.bilateralFilter(gray, 5, 25, 25);

      clahe = cv.createCLAHE(clipLimit: 1.8, tileGridSize: (8, 8));
      claheOut = clahe.apply(denoised);

      // Remove slow-varying illumination before thresholding.
      background = cv.gaussianBlur(claheOut, (0, 0), 15);
      normalized = _illuminationNormalize(claheOut, background);

      final blockSize = _adaptiveBlockSize(
        normalized.cols,
        normalized.rows,
      );

      binary = cv.adaptiveThreshold(
        normalized,
        255,
        cv.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv.THRESH_BINARY,
        blockSize,
        10,
      );

      // Close tiny gaps in characters. Do not apply MORPH_OPEN by default:
      // on phone photos it can erase thin strokes, punctuation and
      // Vietnamese diacritics.
      kernelClose = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      clean = cv.morphologyEx(
        binary,
        cv.MORPH_CLOSE,
        kernelClose,
        iterations: 1,
      );

      return clean;
    } finally {
      _safeDispose(clahe);
      _safeDispose(gray);
      _safeDispose(denoised);
      _safeDispose(claheOut);
      _safeDispose(background);
      _safeDispose(normalized);
      _safeDispose(binary);
      _safeDispose(kernelClose);
      // clean intentionally returned.
    }
  }

  /// Normalize a document illuminated by a non-uniform light field.
  /// Estimates slow-changing illumination from a heavily blurred background
  /// and divides the document image by that field.
  static cv.Mat _illuminationNormalize(
    cv.Mat image,
    cv.Mat background,
  ) {
    // normalized = image / background * target
    final stats = cv.meanStdDev(background);
    final target = stats.$1.val1.clamp(175.0, 225.0);

    cv.Mat? backgroundSafe;
    cv.Mat? image32;
    cv.Mat? background32;

    try {
      // Small floor avoids unstable division in dark/shadow regions.
      backgroundSafe = background.addU8(8);
      image32 = image.convertTo(cv.MatType.CV_32FC1);
      background32 = backgroundSafe.convertTo(cv.MatType.CV_32FC1);

      return cv.divide(
        image32,
        background32,
        scale: target,
        dtype: cv.CV_8UC1,
      );
    } finally {
      _safeDispose(backgroundSafe);
      _safeDispose(image32);
      _safeDispose(background32);
    }
  }

  static int _adaptiveBlockSize(int width, int height) {
    final shortSide = math.min(width, height);
    if (shortSide >= 1800) return 41;
    if (shortSide >= 1200) return 35;
    if (shortSide >= 800) return 31;
    return 25;
  }

  // ==========================================================================
  // JPEG
  // ==========================================================================

  static Uint8List _encodeJpeg(cv.Mat mat, int quality) {
    final params = cv.VecI32.fromList([
      cv.IMWRITE_JPEG_QUALITY,
      quality,
      cv.IMWRITE_JPEG_OPTIMIZE,
      1,
    ]);

    try {
      final (ok, bytes) = cv.imencode(
        '.jpg',
        mat,
        params: params,
      );

      if (!ok || bytes.isEmpty) {
        throw StateError('Không encode JPEG được.');
      }

      return bytes;
    } finally {
      _safeDispose(params);
    }
  }

  // ==========================================================================
  // GEOMETRY
  // ==========================================================================

  static List<cv.Point> _orderQuad(List<cv.Point> points) {
    cv.Point? tl;
    cv.Point? tr;
    cv.Point? br;
    cv.Point? bl;

    var minSum = double.infinity;
    var maxSum = -double.infinity;
    var minDiff = double.infinity;
    var maxDiff = -double.infinity;

    for (final p in points) {
      final sum = p.x + p.y.toDouble();
      final diff = p.x - p.y.toDouble();

      if (sum < minSum) {
        minSum = sum;
        tl = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        br = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        bl = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        tr = p;
      }
    }

    return [tl!, tr!, br!, bl!];
  }

  static double _rectangleScore(List<cv.Point> p) {
    double score = 0;
    for (int i = 0; i < 4; i++) {
      final a = p[(i + 3) % 4];
      final b = p[i];
      final c = p[(i + 1) % 4];

      final abx = a.x - b.x;
      final aby = a.y - b.y;
      final cbx = c.x - b.x;
      final cby = c.y - b.y;

      final dot = abx * cbx + aby * cby;
      final mag = math.sqrt(
        (abx * abx + aby * aby) * (cbx * cbx + cby * cby),
      );

      if (mag == 0) continue;
      final cosine = (dot / mag).abs();
      score += 1.0 - cosine.clamp(0.0, 1.0);
    }
    return score / 4.0;
  }

  static double _borderCoverageBonus(
    List<cv.Point> p,
    int width,
    int height,
  ) {
    final margin = math.min(width, height) * 0.04;
    int nearBorder = 0;
    for (final point in p) {
      if (point.x <= margin ||
          point.y <= margin ||
          point.x >= width - margin ||
          point.y >= height - margin) {
        nearBorder++;
      }
    }
    return nearBorder / 4.0;
  }

  static double _distance(cv.Point a, cv.Point b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  // ==========================================================================
  // EXIF ORIENTATION NORMALIZATION
  // ==========================================================================

  static Uint8List _normalizeExifOrientation(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    try {
      final orientation = decoded.exif.imageIfd.orientation;

      // Skip needless decode→rotate→encode→decode round-trip in common case.
      if (orientation == null || orientation == 1) {
        return bytes;
      }

      final oriented = img.bakeOrientation(decoded);
      return img.encodeJpg(oriented, quality: 100);
    } catch (_) {
      return bytes;
    }
  }

  // ==========================================================================
  // PURE DART FALLBACK
  // ==========================================================================

  static Uint8List? _processWithDartFallback(
    Uint8List bytes,
    ScanMode mode,
    int maxWidth,
    int jpegQuality,
  ) {
    try {
      var im = img.decodeImage(bytes);
      if (im == null) return null;

      im = img.bakeOrientation(im);

      if (im.width > maxWidth) {
        im = img.copyResize(
          im,
          width: maxWidth,
          interpolation: img.Interpolation.cubic,
        );
      }

      switch (mode) {
        case ScanMode.color:
          im = img.adjustColor(
            im,
            brightness: 1.02,
            contrast: 1.10,
            saturation: 1.02,
          );
          im = _dartUnsharpMask(im, amount: 0.45, radius: 1);
          break;

        case ScanMode.grayscale:
          im = img.grayscale(im);
          im = img.adjustColor(
            im,
            brightness: 1.03,
            contrast: 1.18,
          );
          im = _dartUnsharpMask(im, amount: 0.60, radius: 1);
          break;

        case ScanMode.bw:
          im = img.grayscale(im);
          im = img.adjustColor(
            im,
            brightness: 1.03,
            contrast: 1.12,
          );
          im = _dartAdaptiveThreshold(im, windowSize: 41, k: 0.13);
          break;
      }

      return img.encodeJpg(im, quality: jpegQuality);
    } catch (_) {
      return null;
    }
  }

  static img.Image _dartUnsharpMask(
    img.Image src, {
    double amount = 0.5,
    int radius = 1,
  }) {
    final blurred = img.gaussianBlur(src, radius: radius);
    final out = img.Image(width: src.width, height: src.height);

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final b = blurred.getPixel(x, y);

        final r = (p.r + amount * (p.r - b.r)).clamp(0, 255).round();
        final g = (p.g + amount * (p.g - b.g)).clamp(0, 255).round();
        final bl = (p.b + amount * (p.b - b.b)).clamp(0, 255).round();

        out.setPixelRgb(x, y, r, g, bl);
      }
    }
    return out;
  }

  static img.Image _dartAdaptiveThreshold(
    img.Image src, {
    int windowSize = 41,
    double k = 0.13,
  }) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);

    final stride = w + 1;
    final integral = Uint32List((h + 1) * stride);

    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        rowSum += l;
        integral[(y + 1) * stride + x + 1] =
            integral[y * stride + x + 1] + rowSum;
      }
    }

    final half = windowSize ~/ 2;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w);
        final y1 = (y - half).clamp(0, h);
        final x2 = (x + half + 1).clamp(0, w);
        final y2 = (y + half + 1).clamp(0, h);

        final count = (x2 - x1) * (y2 - y1);
        final sum = integral[y2 * stride + x2] -
            integral[y1 * stride + x2] -
            integral[y2 * stride + x1] +
            integral[y1 * stride + x1];

        final avg = sum / count;
        final p = src.getPixel(x, y);
        final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final v = l < avg * (1 - k) ? 0 : 255;
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  // ==========================================================================
  // RESOURCE HELPERS
  // ==========================================================================

  /// Best-effort dispose. Wrapped in try-catch because:
  ///  1) Disposing an already-disposed native object throws.
  ///  2) Not every opencv_dart version exposes `isDisposed` on every type.
  ///     Checking it can cause a compile error on some versions.
  static void _safeDispose(Object? object) {
    if (object == null) return;
    try {
      if (object is cv.Mat) {
        object.dispose();
      } else if (object is cv.VecPoint) {
        object.dispose();
      } else if (object is cv.Contours) {
        object.dispose();
      } else if (object is cv.VecVec4i) {
        object.dispose();
      } else if (object is cv.VecI32) {
        object.dispose();
      } else if (object is cv.CLAHE) {
        object.dispose();
      }
    } catch (_) {
      // Already disposed or type not supported — ignore.
    }
  }
}

class _QuadCandidate {
  final List<cv.Point> points;
  final double score;
  final double areaRatio;

  const _QuadCandidate({
    required this.points,
    required this.score,
    required this.areaRatio,
  });
}

class _ProcessArgs {
  final List<String> paths;
  final int mode;
  final int jpegQuality;
  final int maxWidth;

  const _ProcessArgs({
    required this.paths,
    required this.mode,
    required this.jpegQuality,
    required this.maxWidth,
  });
}
