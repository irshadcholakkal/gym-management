import 'dart:js_interop';

@JS('window.addEventListener')
external void _listen(JSString type, JSFunction callback);
@JS('window.removeEventListener')
external void _remove(JSString type, JSFunction callback);
void Function() onConnectivityRestored(void Function() callback) {
  final listener = ((JSAny? event) => callback()).toJS;
  _listen('online'.toJS, listener);
  return () => _remove('online'.toJS, listener);
}
