import 'dart:js_interop';

@JS('gymproPushSubscribe')
external JSPromise<JSString> _subscribe(JSString key);
Future<String> subscribePush(String key) async =>
    (await _subscribe(key.toJS).toDart).toDart;
