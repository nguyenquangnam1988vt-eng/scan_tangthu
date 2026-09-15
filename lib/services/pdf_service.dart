import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/session.dart';

/// Ghép ảnh (đã được flutter_better_scanner xử lý) thành PDF.
///
/// Vì scanner đã làm auto-crop + enhance + filter, service này không cần
/// CLAHE / illumination / adaptive threshold nữa. Chỉ cần:
///   1) Đọc ảnh
///   2) Resize nếu quá lớn (giảm dung lượng)
///   3) Encode JPEG chất lượng cao
///   4) Ghép vào A4 PDF
class PdfService {
  static Future<File> createPdf({
    required List<String> imagePaths,
    required String outputPath,
    required ScanMode mode,
    int jpegQuality = 90,
    int maxWidth = 2400,
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('imagePaths không được rỗng.');
    }
    if (outputPath.trim().isEmpty) {
      throw ArgumentError('outputPath không hợp lệ.');
    }

    final jpgBytesList = await compute(
      _processImages,
      _ProcessArgs(
        paths: imagePaths,
        mode: mode.index,
        jpegQuality: jpegQuality,
        maxWidth: maxWidth,
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
        final f = File(path);
        if (!await f.exists()) continue;

        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;

        var im = img.decodeImage(bytes);
        if (im == null) continue;

        im = img.bakeOrientation(im);

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

        switch (mode) {
          case ScanMode.color:
            // Giữ nguyên ảnh scanner trả về.
            break;
          case ScanMode.grayscale:
            im = img.grayscale(im);
            break;
          case ScanMode.bw:
            im = img.grayscale(im);
            im = img.luminanceThreshold(im, threshold: 0.55);
            break;
        }

        result.add(img.encodeJpg(im, quality: args.jpegQuality));
      } catch (_) {
        continue;
      }
    }
    return result;
  }
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
