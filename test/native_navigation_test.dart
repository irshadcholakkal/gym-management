import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_saas/core/navigation.dart';

void main() {
  for (final initial in ['/', '/members']) {
    testWidgets('Native back restores screens and closes dialogs from $initial',
        (tester) async {
      final router = GoRouter(initialLocation: initial, routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Text('Overview screen'),
              routes: [
                for (final name in ['members', 'receipts'])
                  GoRoute(
                    path: name,
                    builder: (context, _) => Column(children: [
                      Text('$name screen'),
                      TextButton(
                        onPressed: () => context.navigateTo('/receipts'),
                        child: const Text('Open receipts'),
                      ),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const AlertDialog(
                            title: Text('Document dialog'),
                          ),
                        ),
                        child: const Text('Open dialog'),
                      ),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      if (initial == '/') {
        final context = tester.element(find.text('Overview screen'));
        context.navigateTo('/members');
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Open receipts'));
      await tester.pumpAndSettle();
      expect(find.text('receipts screen'), findsOneWidget);
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Document dialog'), findsNothing);
      expect(find.text('receipts screen'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('members screen'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Overview screen'), findsOneWidget);
      expect(router.canPop(), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
