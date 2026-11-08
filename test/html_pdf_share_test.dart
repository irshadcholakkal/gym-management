import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:gym_saas/features/receipts/presentation/receipt_preview_native.dart';

class HtmlPrinting extends PrintingPlatform {
  bool supported = true;
  String? renderedHtml;
  String? sharedName;
  Uint8List? sharedBytes;
  final pdf = Uint8List.fromList('%PDF-test'.codeUnits);

  @override
  Future<PrintingInfo> info() async =>
      PrintingInfo(canConvertHtml: supported, canShare: supported);

  @override
  Future<Uint8List> convertHtml(
      String html, String? baseUrl, PdfPageFormat format) async {
    renderedHtml = html;
    expect(format, PdfPageFormat.a4);
    return pdf;
  }

  @override
  Future<bool> sharePdf(Uint8List bytes, String filename, Rect bounds,
      String? subject, String? body, List<String>? emails) async {
    sharedName = filename;
    sharedBytes = bytes;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Native sharing converts the custom HTML and shares the resulting PDF',
      () async {
    final original = PrintingPlatform.instance;
    final platform = HtmlPrinting();
    PrintingPlatform.instance = platform;
    addTearDown(() => PrintingPlatform.instance = original);
    const html = '<html><style>h1{color:red}</style><h1>INV-0007</h1></html>';
    expect(await shareReceiptHtmlPdf(html, 'INV-0007'), isTrue);
    expect(platform.renderedHtml, html);
    expect(platform.sharedName, 'INV-0007.pdf');
    expect(platform.sharedBytes, same(platform.pdf));
  });

  test('Unsupported platforms do not share an empty or substitute document',
      () async {
    final original = PrintingPlatform.instance;
    final platform = HtmlPrinting()..supported = false;
    PrintingPlatform.instance = platform;
    addTearDown(() => PrintingPlatform.instance = original);
    expect(await shareReceiptHtmlPdf('<h1>Invoice</h1>', 'INV-0007'), isFalse);
    expect(platform.renderedHtml, isNull);
    expect(platform.sharedBytes, isNull);
  });
}
