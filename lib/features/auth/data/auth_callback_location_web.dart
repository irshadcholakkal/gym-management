import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? data, JSString title, JSString url);

void clearAuthCallbackLocation() => _replaceState(null, ''.toJS, '/'.toJS);
