import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'session_service.dart';

class ExportService {
  /// Nén thư mục hồ sơ thành ZIP rồi mở share sheet.
  /// Nếu [password] != null và không rỗng → mã hóa AES-256.
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

    // archive 4.x: password truyền vào constructor của ZipFileEncoder
    final encoder = hasPassword
        ? ZipFileEncoder(password: password)
        : ZipFileEncoder();

    encoder.create(zipPath);
    await encoder.addDirectory(caseDir, includeDirName: true);
    encoder.close();

    await Share.shareXFiles(
      [XFile(zipPath, mimeType: 'application/zip')],
      subject: safeName,
      text: hasPassword
          ? 'Hồ sơ: $safeName (đã bảo vệ bằng mật khẩu)'
          : 'Hồ sơ: $safeName',
    );

    try {
      await zipFile.delete();
    } catch (_) {}
  }
}
