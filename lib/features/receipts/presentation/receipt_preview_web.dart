import 'dart:js_interop';

@JS('gymproReceiptPreview')
external void _preview(JSString html, JSString title);

@JS('gymproReceiptSharePdf')
external JSPromise<JSAny?> _sharePdf(JSString html, JSString title);

Future<bool> shareReceiptHtmlPdf(String html, String title) async {
  await _sharePdf(html.toJS, title.toJS).toDart;
  return true;
}

Future<bool> previewReceiptHtml(String html, String title) async {
  _preview(html.toJS, title.toJS);
  return true;
}
