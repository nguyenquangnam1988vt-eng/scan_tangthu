import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'session_service.dart';

class ExportService {
  static Future<ShareResult> shareCase(String caseName) async {
    final caseDir = await SessionService.getCaseDir(caseName);
    if (!await caseDir.exists()) {
      throw Exception('Hồ sơ chưa có file nào');
    }

    final temp = await getTemporaryDirectory();
    final safeName = caseName.trim().isEmpty ? 'HoSo' : caseName.trim();
    final zipPath = '${temp.path}/$safeName.zip';
    final zipFile = File(zipPath);
    if (await zipFile.exists()) await zipFile.delete();

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(caseDir, includeDirName: true);
    await encoder.close();

    final result = await Share.shareXFiles(
      [XFile(zipPath, mimeType: 'application/zip')],
      subject: safeName,
      text: 'Hồ sơ: $safeName',
    );

    try {
      await zipFile.delete();
    } catch (_) {}

    return result;
  }
}
