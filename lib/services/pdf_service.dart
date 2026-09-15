import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/session.dart';

class PdfService {
  /// Ghép ảnh → PDF với chất lượng cao.
  /// Chạy trong isolate để không block UI.
  static Future<File> createPdf({
    required List<String> imagePaths,
    required String outputPath,
    required ScanMode mode,
    int jpegQuality = 92,
    int maxWidth = 2200,
  }) async {
    final jpgBytesList = await compute(
      _processImages,
      _ProcessArgs(
        paths: imagePaths,
        mode: mode.index,
        jpegQuality: jpegQuality,
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

  // ---------- ISOLATE ENTRYPOINT ----------
  static Future<List<Uint8List>> _processImages(_ProcessArgs args) async {
    final mode = ScanMode.values[args.mode];
    final result = <Uint8List>[];

    for (final path in args.paths) {
      final bytes = await File(path).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) continue;

      // 1. Xoay đúng chiều EXIF
      im = img.bakeOrientation(im);

      // 2. Resize nếu quá lớn (giữ chi tiết chữ nhỏ)
      if (im.width > args.maxWidth) {
        im = img.copyResize(
          im,
          width: args.maxWidth,
          interpolation: img.Interpolation.cubic,
        );
      }

      // 3. Tăng chất lượng theo chế độ
      im = _enhance(im, mode);

      // 4. Encode JPEG chất lượng cao
      final jpg = img.encodeJpg(im, quality: args.jpegQuality);
      result.add(jpg);
    }

    return result;
  }

  // ---------- PIPELINE XỬ LÝ ẢNH ----------
  static img.Image _enhance(img.Image src, ScanMode mode) {
    var im = src;

    // Bước 1: Auto-contrast — kéo giãn histogram cho ảnh tươi hơn
    im = _autoContrast(im);

    switch (mode) {
      case ScanMode.color:
        // Màu: tăng sáng nhẹ + tương phản + làm nét vừa
        im = img.adjustColor(
          im,
          brightness: 1.06,
          contrast: 1.20,
          saturation: 1.05,
        );
        im = _unsharpMask(im, amount: 0.7, radius: 1);
        return im;

      case ScanMode.grayscale:
        // Xám: chuyển xám + tăng tương phản mạnh + làm nét rõ
        im = img.grayscale(im);
        im = img.adjustColor(
          im,
          brightness: 1.10,
          contrast: 1.40,
        );
        im = _unsharpMask(im, amount: 0.9, radius: 1);
        return im;

      case ScanMode.bw:
        // Đen trắng: adaptive threshold — chữ rất nét, không vỡ
        im = img.grayscale(im);
        im = img.adjustColor(im, brightness: 1.08, contrast: 1.25);
        im = _adaptiveThreshold(im, windowSize: 35, k: 0.15);
        return im;
    }
  }

  // ---------- AUTO CONTRAST ----------
  /// Kéo giãn histogram: đưa mức sáng/tối về 0-255.
  static img.Image _autoContrast(img.Image src, {double clip = 0.005}) {
    // Đếm histogram độ sáng
    final hist = List<int>.filled(256, 0);
    for (final p in src) {
      final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      hist[l.clamp(0, 255)]++;
    }

    final total = src.width * src.height;
    final cut = (total * clip).round();

    // Tìm ngưỡng thấp
    int low = 0, sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += hist[i];
      if (sum > cut) {
        low = i;
        break;
      }
    }

    // Tìm ngưỡng cao
    int high = 255;
    sum = 0;
    for (int i = 255; i >= 0; i--) {
      sum += hist[i];
      if (sum > cut) {
        high = i;
        break;
      }
    }

    if (high <= low) return src;
    final scale = 255.0 / (high - low);

    final out = img.Image(width: src.width, height: src.height);
    for (final p in src) {
      final nr = ((p.r - low) * scale).clamp(0, 255).toInt();
      final ng = ((p.g - low) * scale).clamp(0, 255).toInt();
      final nb = ((p.b - low) * scale).clamp(0, 255).toInt();
      out.setPixelRgb(p.x, p.y, nr, ng, nb);
    }
    return out;
  }

  // ---------- UNSHARP MASK ----------
  /// Làm nét kiểu "Unsharp Mask": ảnh gốc + hệ số * (gốc - blur).
  static img.Image _unsharpMask(
    img.Image src, {
    double amount = 0.8,
    int radius = 1,
  }) {
    final blurred = img.gaussianBlur(src, radius: radius);
    final out = img.Image(width: src.width, height: src.height);

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final b = blurred.getPixel(x, y);

        final r = (p.r + amount * (p.r - b.r)).clamp(0, 255).toInt();
        final g = (p.g + amount * (p.g - b.g)).clamp(0, 255).toInt();
        final bl = (p.b + amount * (p.b - b.b)).clamp(0, 255).toInt();

        out.setPixelRgb(x, y, r, g, bl);
      }
    }
    return out;
  }

  // ---------- ADAPTIVE THRESHOLD (BRADLEY) ----------
  /// Ngưỡng đen trắng động theo vùng — chữ rất nét, không vỡ như threshold cố định.
  /// [windowSize] kích thước cửa sổ điểm ảnh, [k] hệ số điều chỉnh (0.1–0.2).
  static img.Image _adaptiveThreshold(
    img.Image src, {
    int windowSize = 35,
    double k = 0.15,
  }) {
    final w = src.width, h = src.height;
    final out = img.Image(width: w, height: h);

    // 1. Tính Integral Image (tổng lũy tích) — truy vấn tổng vùng O(1)
    final integral = List.generate(
      h + 1,
      (_) => List<int>.filled(w + 1, 0),
      growable: false,
    );

    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        rowSum += l;
        integral[y + 1][x + 1] = integral[y][x + 1] + rowSum;
      }
    }

    // 2. Duyệt từng pixel, so sánh với trung bình vùng
    final half = windowSize ~/ 2;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w);
        final y1 = (y - half).clamp(0, h);
        final x2 = (x + half + 1).clamp(0, w);
        final y2 = (y + half + 1).clamp(0, h);

        final count = (x2 - x1) * (y2 - y1);
        final sum = integral[y2][x2] -
            integral[y1][x2] -
            integral[y2][x1] +
            integral[y1][x1];
        final avg = sum / count;

        final p = src.getPixel(x, y);
        final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b);

        // Pixel tối hơn (1-k) lần trung bình → đen, ngược lại → trắng
        final v = l < avg * (1 - k) ? 0 : 255;
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }
}

// ---------- ARGS CHO ISOLATE ----------
class _ProcessArgs {
  final List<String> paths;
  final int mode;
  final int jpegQuality;
  final int maxWidth;

  _ProcessArgs({
    required this.paths,
    required this.mode,
    required this.jpegQuality,
    required this.maxWidth,
  });
}
