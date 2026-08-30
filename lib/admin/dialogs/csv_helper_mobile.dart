import 'dart:io';
import 'package:file_picker/file_picker.dart';

void downloadCSV(String csvContent, String fileName) async {
  try {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save CSV Template',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsString(csvContent);
    }
  } catch (e) {
    // Fallback if platform does not support saveFile
  }
}

void downloadBytes(List<int> bytes, String fileName, {String mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}) async {
  try {
    final ext = fileName.contains('.') ? fileName.split('.').last : 'xlsx';
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Template',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [ext],
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
    }
  } catch (e) {
    // Fallback if platform does not support saveFile
  }
}

void triggerImportAndExport(String url) {
  // Mobile stub/implementation
}

