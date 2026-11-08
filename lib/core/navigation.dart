import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension AppNavigation on BuildContext {
  /// Browser navigation owns its history; native navigation needs a page stack.
  void navigateTo(String location) {
    final router = GoRouter.of(this);
    if (router.routeInformationProvider.value.uri.toString() == location) {
      return;
    }
    if (kIsWeb || location == '/') {
      router.go(location);
    } else {
      router.push<void>(location);
    }
  }
}
