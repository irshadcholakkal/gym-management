import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme.dart';
import '../data/auth_repository.dart';

class GymSetupPage extends StatefulWidget {
  const GymSetupPage({
    super.key,
    required this.repository,
    required this.onComplete,
    required this.onSignOut,
  });
  final AuthRepository repository;
  final Future<void> Function() onComplete, onSignOut;
  @override
  State<GymSetupPage> createState() => _GymSetupPageState();
}

class _GymSetupPageState extends State<GymSetupPage> {
  final _form = GlobalKey<FormState>(), _name = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createGym(_name.text.trim());
      await widget.onComplete();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to create your gym. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.fitness_center_rounded,
                      size: 42,
                      color: GymTheme.sage,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Set up your gym',
                      style: Theme.of(context).textTheme.headlineLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your account is verified. Create a workspace for your own gym to get started.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Gym name',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Enter your gym name'
                          : null,
                      onFieldSubmitted: (_) => _create(),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _create,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create gym workspace'),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text(
                      'Joining an existing gym? Ask its administrator to invite you. Creating a workspace here makes a separate gym.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF657570)),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _retry,
                      child: const Text('Check invitation access'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : widget.onSignOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
