import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/session_cubit.dart';
import 'theme.dart';
import 'workspace.dart';

class GymProApp extends StatefulWidget {
  const GymProApp({super.key, this.client});
  final SupabaseClient? client;
  @override
  State<GymProApp> createState() => _GymProAppState();
}

class _GymProAppState extends State<GymProApp> with WidgetsBindingObserver {
  SessionCubit? _session;
  AuthRepository? _auth;
  StreamSubscription<SessionState>? _subscription;
  final _refresh = RouterRefresh();
  late final GoRouter _router;
  late final SemanticsHandle _semantics;
  @override
  void initState() {
    super.initState();
    _semantics = WidgetsBinding.instance.ensureSemantics();
    WidgetsBinding.instance.addObserver(this);
    if (widget.client != null) {
      _auth = SupabaseAuthRepository(widget.client!);
      _session = SessionCubit(_auth!);
      _subscription = _session!.stream.listen((_) => _refresh.refresh());
    }
    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: _refresh,
      redirect: (context, state) {
        if (_session == null) {
          return state.uri.path == '/setup' ? null : '/setup';
        }
        final session = _session!.state, path = state.uri.path;
        if (session.status == SessionStatus.loading) {
          return path == '/loading' ? null : '/loading';
        }
        if (session.status == SessionStatus.recovery) {
          return path == '/recovery' ? null : '/recovery';
        }
        if (session.status == SessionStatus.denied) {
          return path == '/access' ? null : '/access';
        }
        if (session.status != SessionStatus.signedIn) {
          return path == '/login' ? null : '/login';
        }
        if (['/loading', '/login', '/setup', '/access'].contains(path)) {
          return '/';
        }
        if (!session.access!.allows(path)) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/setup', builder: (_, _) => const SetupPage()),
        GoRoute(
          path: '/loading',
          builder: (_, _) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => LoginPage(repository: _auth!),
        ),
        GoRoute(
          path: '/recovery',
          builder: (_, _) =>
              LoginPage(repository: _auth!, recoveryClient: widget.client),
        ),
        GoRoute(
          path: '/access',
          builder: (_, _) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_session!.state.message ?? 'Access unavailable'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _session!.restore,
                      child: const Text('Verify access again'),
                    ),
                    TextButton(
                      onPressed: _session!.signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ShellRoute(
          builder: (_, state, child) => Workspace(
            key: ValueKey(
              '${_session!.state.access!.gymId}:${_session!.state.access!.userId}:${_session!.state.access!.role.name}',
            ),
            access: _session!.state.access!,
            client: widget.client!,
            session: _session!,
            path: state.uri.path,
            child: child,
          ),
          routes: [
            for (final path in [
              '/',
              '/members',
              '/packages',
              '/subscriptions',
              '/payments',
              '/receipts',
              '/employees',
              '/notifications',
              '/settings',
              '/sync',
            ])
              GoRoute(
                path: path,
                builder: (_, _) => WorkspaceContent(path: path),
              ),
          ],
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Page not found. Go to dashboard'),
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_session?.restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _router.dispose();
    _refresh.dispose();
    _session?.close();
    _semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'GymPro UAE',
    debugShowCheckedModeBanner: false,
    theme: GymTheme.light,
    routerConfig: _router,
  );
}

class RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.fitness_center_rounded,
                    color: GymTheme.sage,
                    size: 44,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to GymPro UAE',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text('Connect your gym’s secure workspace'),
                  const SizedBox(height: 24),
                  const Text(
                    'Apply the Supabase migrations, provision your owner account, then run the app with your project URL and public anonymous key.',
                  ),
                  const SizedBox(height: 20),
                  const SelectableText(
                    'flutter run -d chrome\n  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co\n  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'See README.md for setup and verification status. Real gym data appears after authentication; no sample financial records are created.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
