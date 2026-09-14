import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfPreviewScreen extends StatelessWidget {
  final File file;
  final String title;

  const PdfPreviewScreen({
    super.key,
    required this.file,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: PdfPreview(
        build: (format) => file.readAsBytes(),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        useActions: true,
        pdfFileName: title,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}