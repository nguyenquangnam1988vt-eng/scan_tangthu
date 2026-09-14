import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/session.dart';

class PdfService {
  /// Ghép ảnh → PDF với chế độ Màu/Xám/BW, có tăng sáng + nén.
  static Future<File> createPdf({
    required List<String> imagePaths,
    required String outputPath,
    required ScanMode mode,
    int jpegQuality = 80,
    int maxWidth = 1700,
  }) async {
    final doc = pw.Document(compress: true);

    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) continue;

      // 1. Xoay đúng chiều EXIF
      decoded = img.bakeOrientation(decoded);

      // 2. Resize nếu quá lớn
      if (decoded.width > maxWidth) {
        decoded = img.copyResize(
          decoded,
          width: maxWidth,
          interpolation: img.Interpolation.average,
        );
      }

      // 3. Tăng sáng + tương phản + chuyển mode
      final enhanced = _enhance(decoded, mode);

      // 4. Encode JPEG
      final jpg = img.encodeJpg(enhanced, quality: jpegQuality);

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

  static img.Image _enhance(img.Image src, ScanMode mode) {
    switch (mode) {
      case ScanMode.color:
        // Tăng sáng nhẹ + tương phản vừa
        return img.adjustColor(
          src,
          brightness: 1.10,
          contrast: 1.18,
          saturation: 1.05,
        );

      case ScanMode.grayscale:
        // Xám: nhẹ file hơn 40%, chữ vẫn rõ
        final gray = img.grayscale(src);
        return img.adjustColor(
          gray,
          brightness: 1.15,
          contrast: 1.30,
        );

      case ScanMode.bw:
        // Đen trắng: nhẹ nhất, phù hợp tài liệu in
        final gray = img.grayscale(src);
        final boosted = img.adjustColor(
          gray,
          brightness: 1.20,
          contrast: 1.40,
        );
        return img.luminanceThreshold(boosted, threshold: 0.55);
    }
  }
}