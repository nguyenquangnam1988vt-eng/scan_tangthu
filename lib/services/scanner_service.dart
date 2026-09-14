import 'package:cunning_document_scanner/cunning_document_scanner.dart';

class ScannerService {
  static Future<List<String>?> scan() async {
    return CunningDocumentScanner.getPictures(
      noOfPages: 30,
      isGalleryImportAllowed: true,
    );
  }
}