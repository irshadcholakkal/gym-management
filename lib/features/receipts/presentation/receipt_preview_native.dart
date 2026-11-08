import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

Future<bool> previewReceiptHtml(String html, String title) async => false;

Future<bool> shareReceiptHtmlPdf(String html, String title) async {
  final info = await Printing.info();
  if (!info.canConvertHtml || !info.canShare) return false;
  // The platform HTML renderer preserves the saved document's CSS and layout.
  final bytes =
      // ignore: deprecated_member_use
      await Printing.convertHtml(html: html, format: PdfPageFormat.a4);
  return Printing.sharePdf(
      bytes: bytes, filename: '$title.pdf', subject: title);
}
