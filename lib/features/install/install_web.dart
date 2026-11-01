import 'dart:js_interop';

@JS('gymproInstallState')
external JSString _state();
@JS('gymproInstallApp')
external JSPromise<JSString> _install();
String appInstallState() => _state().toDart;
Future<String> installApp() async => (await _install().toDart).toDart;
