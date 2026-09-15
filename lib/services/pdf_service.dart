import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/session.dart';

class PdfService {
  static Future<File> createPdf({
    required List<String> imagePaths,
    required String outputPath,
    required ScanMode mode,
    int maxWidth = 2400,
  }) async {
    final jpgBytesList = await compute(
      _processImages,
      _ProcessArgs(
        paths: imagePaths,
        mode: mode.index,
        maxWidth: maxWidth,
      ),
    );

    final doc = pw.Document(compress: true);
    for (final jpg in jpgBytesList) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(4),
          build: (_) => pw.Center(
            child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final file = File(outputPath);
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<List<Uint8List>> _processImages(_ProcessArgs args) async {
    final mode = ScanMode.values[args.mode];
    final result = <Uint8List>[];

    for (final path in args.paths) {
      final bytes = await File(path).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) continue;

      // 1. Xoay EXIF
      im = img.bakeOrientation(im);

      // 2. Resize nếu quá lớn — giữ tỷ lệ, dùng cubic
      if (im.width > args.maxWidth) {
        final ratio = args.maxWidth / im.width;
        final newH = (im.height * ratio).round();
        im = img.copyResize(
          im,
          width: args.maxWidth,
          height: newH,
          interpolation: img.Interpolation.cubic,
        );
      }

      // 3. Pipeline theo mode
      switch (mode) {
        case ScanMode.color:
          im = _processColor(im);
          break;
        case ScanMode.grayscale:
          im = _processGrayscale(im);
          break;
        case ScanMode.bw:
          im = _processBW(im);
          break;
      }

      final quality = mode == ScanMode.color ? 90 : 88;
      result.add(img.encodeJpg(im, quality: quality));
    }

    return result;
  }

  // ============================================================
  // COLOR PIPELINE
  // original → denoise nhẹ → contrast nhẹ → unsharp 0.6 → JPEG
  // ============================================================
  static img.Image _processColor(img.Image src) {
    var im = src;
    im = img.medianFilter(im, radius: 1);
    im = img.adjustColor(im, contrast: 1.10, brightness: 1.02);
    im = _unsharpMask(im, amount: 0.6, radius: 1);
    return im;
  }

  // ============================================================
  // GRAYSCALE PIPELINE
  // gray → denoise → illumination normalize → CLAHE nhẹ → unsharp 0.7
  // ============================================================
  static img.Image _processGrayscale(img.Image src) {
    var im = src;
    im = img.grayscale(im);
    im = img.medianFilter(im, radius: 1);
    im = _illuminationNormalize(im, blurRadius: 25); // ⭐ bước then chốt
    im = _clahe(im, tiles: 8, clipLimit: 2.0);
    im = _unsharpMask(im, amount: 0.7, radius: 1);
    return im;
  }

  // ============================================================
  // BW PIPELINE
  // gray → denoise → illumination normalize → adaptive threshold
  //      → morphology open
  // ⚠️ KHÔNG sharpen — adaptive threshold tự làm cạnh rõ
  // ============================================================
  static img.Image _processBW(img.Image src) {
    var im = src;
    im = img.grayscale(im);
    im = img.medianFilter(im, radius: 1);
    im = _illuminationNormalize(im, blurRadius: 25); // ⭐ bước then chốt
    im = _adaptiveThreshold(im, windowSize: 41, k: 0.15);
    im = _morphOpen(im, kernelSize: 2);
    return im;
  }

  // ============================================================
  // ⭐ ILLUMINATION NORMALIZATION
  // Công thức: out = pixel / background * 255
  // background = gaussian blur bán kính lớn của chính ảnh
  // → san phẳng ánh sáng, khử bóng, đều nền giấy
  // ============================================================
  static img.Image _illuminationNormalize(
    img.Image src, {
    int blurRadius = 25,
  }) {
    final bg = img.gaussianBlur(src, radius: blurRadius);
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final b = bg.getPixel(x, y);

        // Dùng kênh R (đã grayscale → R=G=B)
        final lum = p.r.toDouble();
        final bgLum = b.r.toDouble();

        // Chia với epsilon tránh chia cho 0
        final ratio = bgLum < 1 ? 1.0 : lum / bgLum;
        final v = (ratio * 255).clamp(0, 255).toInt();

        out.setPixelRgb(x, y, v, v, v);
      }
    }

    return out;
  }

  // ============================================================
  // CLAHE — Contrast Limited Adaptive Histogram Equalization
  // clipLimit 2.0 (nhẹ), tiles 8×8
  // ============================================================
  static img.Image _clahe(
    img.Image src, {
    int tiles = 8,
    double clipLimit = 2.0,
  }) {
    final w = src.width;
    final h = src.height;
    final tileW = (w / tiles).ceil();
    final tileH = (h / tiles).ceil();

    // Histogram mỗi tile — dùng Int32List cho hiệu quả
    final hists = List.generate(
      tiles,
      (_) => List.generate(tiles, (_) => Int32List(256)),
    );

    for (int ty = 0; ty < tiles; ty++) {
      for (int tx = 0; tx < tiles; tx++) {
        final x0 = tx * tileW;
        final y0 = ty * tileH;
        final x1 = (x0 + tileW).clamp(0, w);
        final y1 = (y0 + tileH).clamp(0, h);
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            final p = src.getPixel(x, y);
            final l = p.r.toInt().clamp(0, 255);
            hists[ty][tx][l]++;
          }
        }
      }
    }

    // Clip + redistribute + tạo LUT
    for (int ty = 0; ty < tiles; ty++) {
      for (int tx = 0; tx < tiles; tx++) {
        final hist = hists[ty][tx];
        final tilePixels = tileW * tileH;
        final clip = (clipLimit * tilePixels / 256).round();
        int excess = 0;
        for (int i = 0; i < 256; i++) {
          if (hist[i] > clip) {
            excess += hist[i] - clip;
            hist[i] = clip;
          }
        }
        final inc = excess ~/ 256;
        for (int i = 0; i < 256; i++) {
          hist[i] += inc;
        }

        int cum = 0;
        for (int i = 0; i < 256; i++) {
          cum += hist[i];
          hist[i] = ((cum / tilePixels) * 255).clamp(0, 255).round();
        }
      }
    }

    // Apply LUT
    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      final ty = (y / tileH).floor().clamp(0, tiles - 1);
      for (int x = 0; x < w; x++) {
        final tx = (x / tileW).floor().clamp(0, tiles - 1);
        final p = src.getPixel(x, y);
        final l = p.r.toInt().clamp(0, 255);
        final newL = hists[ty][tx][l];
        out.setPixelRgb(x, y, newL, newL, newL);
      }
    }

    return out;
  }

  // ============================================================
  // ADAPTIVE THRESHOLD — Bradley
  // Integral image dạng Uint32List phẳng — không tốn RAM
  // Ngưỡng: l < avg * (1 - k) → đen, ngược lại → trắng
  // windowSize phụ thuộc độ phân giải ảnh (2400px → 41 OK)
  // ============================================================
  static img.Image _adaptiveThreshold(
    img.Image src, {
    int windowSize = 41,
    double k = 0.15,
  }) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);

    // Integral image phẳng — 1 Uint32List thay vì List<List<int>>
    final stride = w + 1;
    final integral = Uint32List((w + 1) * (h + 1));

    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final l = p.r.toInt().clamp(0, 255);
        rowSum += l;
        integral[(y + 1) * stride + (x + 1)] =
            integral[y * stride + (x + 1)] + rowSum;
      }
    }

    final half = windowSize ~/ 2;
    for (int y = 0; y < h; y++) {
      final y1 = (y - half).clamp(0, h);
      final y2 = (y + half + 1).clamp(0, h);
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w);
        final x2 = (x + half + 1).clamp(0, w);

        final count = (x2 - x1) * (y2 - y1);
        final sum = integral[y2 * stride + x2] -
            integral[y1 * stride + x2] -
            integral[y2 * stride + x1] +
            integral[y1 * stride + x1];
        final avg = sum / count;

        final p = src.getPixel(x, y);
        final l = p.r.toDouble();
        final v = l < avg * (1 - k) ? 0 : 255;
        out.setPixelRgb(x, y, v, v, v);
      }
    }

    return out;
  }

  // ============================================================
  // MORPHOLOGY OPEN — erode → dilate (xoá đốm nhiễu nhỏ)
  // ============================================================
  static img.Image _morphOpen(img.Image src, {int kernelSize = 2}) {
    var im = _erode(src, kernelSize);
    im = _dilate(im, kernelSize);
    return im;
  }

  static img.Image _erode(img.Image src, int size) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);
    final r = size ~/ 2;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int minV = 255;
        for (int dy = -r; dy <= r; dy++) {
          final ny = (y + dy).clamp(0, h - 1);
          for (int dx = -r; dx <= r; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final v = src.getPixel(nx, ny).r.toInt();
            if (v < minV) minV = v;
          }
        }
        out.setPixelRgb(x, y, minV, minV, minV);
      }
    }
    return out;
  }

  static img.Image _dilate(img.Image src, int size) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);
    final r = size ~/ 2;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int maxV = 0;
        for (int dy = -r; dy <= r; dy++) {
          final ny = (y + dy).clamp(0, h - 1);
          for (int dx = -r; dx <= r; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final v = src.getPixel(nx, ny).r.toInt();
            if (v > maxV) maxV = v;
          }
        }
        out.setPixelRgb(x, y, maxV, maxV, maxV);
      }
    }
    return out;
  }

  // ============================================================
  // UNSHARP MASK — sharp = src + amount * (src - blur)
  // ============================================================
  static img.Image _unsharpMask(
    img.Image src, {
    double amount = 0.7,
    int radius = 1,
  }) {
    final blurred = img.gaussianBlur(src, radius: radius);
    final out = img.Image(width: src.width, height: src.height);

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final b = blurred.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          (p.r + amount * (p.r - b.r)).clamp(0, 255).toInt(),
          (p.g + amount * (p.g - b.g)).clamp(0, 255).toInt(),
          (p.b + amount * (p.b - b.b)).clamp(0, 255).toInt(),
        );
      }
    }
    return out;
  }
}

class _ProcessArgs {
  final List<String> paths;
  final int mode;
  final int maxWidth;

  _ProcessArgs({
    required this.paths,
    required this.mode,
    required this.maxWidth,
  });
}
