// Dùng khi chạy trên Windows — không có camera, chọn ảnh từ máy
import 'package:file_picker/file_picker.dart';

class ScannerService {
  static Future<List<String>?> scan() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return null;
    return result.paths.whereType<String>().toList();
  }
}