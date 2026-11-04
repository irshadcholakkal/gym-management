import 'dart:js_interop';

@JS('gymproPushSubscribe')
external JSPromise<JSString> _subscribe(JSString key);
Future<String> subscribePush(String key) async =>
    (await _subscribe(key.toJS).toDart).toDart;

@JS('gymproPushStatus')
external JSPromise<JSString> _status();
Future<String> pushDeviceStatus() async => (await _status().toDart).toDart;

@JS('gymproPushTestDisplay')
external JSPromise<JSAny?> _testDisplay();
Future<void> testPushDisplay() async {
  await _testDisplay().toDart;
}
