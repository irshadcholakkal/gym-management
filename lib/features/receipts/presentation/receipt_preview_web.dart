import 'dart:js_interop';

@JS('gymproReceiptPreview')
external void _preview(JSString html, JSString title);
Future<bool> previewReceiptHtml(String html, String title) async {
  _preview(html.toJS, title.toJS);
  return true;
}
