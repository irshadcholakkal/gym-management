Future<String> subscribePush(String key) async => throw UnsupportedError(
      'Browser push is available in the installed web application.',
    );

Future<String> pushDeviceStatus() async =>
    '{"permission":"unsupported","subscription":null}';
