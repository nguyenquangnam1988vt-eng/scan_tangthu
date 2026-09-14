import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'session_service.dart';

class ExportService {
  /// Nén thư mục hồ sơ thành ZIP rồi mở share sheet.
  /// Nếu [password] != null và không rỗng → mã hóa ZIP bằng AES-256.
  static Future<void> shareCase(
    String caseName, {
    String? password,
  }) async {
    final caseDir = await SessionService.getCaseDir(caseName);
    if (!await caseDir.exists()) {
      throw Exception('Hồ sơ chưa có file nào');
    }

    final temp = await getTemporaryDirectory();
    final safeName = caseName.trim().isEmpty ? 'HoSo' : caseName.trim();
    final zipPath = '${temp.path}/$safeName.zip';
    final zipFile = File(zipPath);
    if (await zipFile.exists()) await zipFile.delete();

    final hasPassword = password != null && password.trim().isNotEmpty;

    if (!hasPassword) {
      // Không có mật khẩu → streaming (nhẹ RAM, nhanh)
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addDirectory(caseDir, includeDirName: true);
      await encoder.close();
    } else {
      // Có mật khẩu → đọc vào memory rồi encode với AES-256
      final archive = Archive();
      final basePath = caseDir.parent.path;

      await for (final entity in caseDir.list(recursive: true)) {
        if (entity is File) {
          final relPath = entity.path
              .substring(basePath.length + 1)
              .replaceAll('\\', '/');
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
        }
      }

      final zipBytes = ZipEncoder().encode(
        archive,
        password: password,
        level: Deflate.BEST_SPEED,
      );

      if (zipBytes == null) {
        throw Exception('Không thể mã hóa ZIP');
      }
      await zipFile.writeAsBytes(zipBytes);
    }

    await Share.shareXFiles(
      [XFile(zipPath, mimeType: 'application/zip')],
      subject: safeName,
      text: hasPassword
          ? 'Hồ sơ: $safeName (đã bảo vệ bằng mật khẩu)'
          : 'Hồ sơ: $safeName',
    );

    // Xoá file tạm sau khi share sheet đóng
    try {
      await zipFile.delete();
    } catch (_) {}
  }
}