// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void downloadCSV(String csvContent, String fileName) {
  try {
    final blob = html.Blob([csvContent], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", fileName);
    
    // Some browsers require appending the element to the document body to trigger download
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    
    // Delay revoking the URL to give the browser time to initiate the download
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
  } catch (e) {
    // Fallback if dynamic browser execution blocks direct anchor download
  }
}

void downloadBytes(List<int> bytes, String fileName, {String mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}) {
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", fileName);
    
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
  } catch (e) {
    // Fallback if dynamic browser execution blocks direct anchor download
  }
}

void triggerImportAndExport(String url) {
  try {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "room_master_export.csv");
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } catch (e) {
    // Fallback if browser blocks popups
  }
}
