import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config.dart';
import '../../../core/theme.dart';
import '../data/auth_repository.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({
    super.key,
    required this.repository,
    required this.onSignIn,
  });
  final AuthRepository repository;
  final VoidCallback onSignIn;
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false,
      _obscure = true,
      _submitted = false,
      _confirmationRequired = true;
  String? _error;
  @override
  void dispose() {
    for (final controller in [_name, _email, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final confirmationRequired = await widget.repository.signUp(
        fullName: _name.text.trim(),
        email: _email.text.trim().toLowerCase(),
        password: _password.text,
        redirect: AppConfig.registrationRedirect,
      );
      if (mounted) {
        _password.clear();
        _confirm.clear();
        setState(() {
          _submitted = true;
          _confirmationRequired = confirmationRequired;
        });
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to create your account. Check your connection and try again.',
        );
      }
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
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: AutofillGroup(
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
                      const SizedBox(height: 18),
                      Text(
                        _submitted
                            ? (_confirmationRequired
                                  ? 'Check your email'
                                  : 'Account created')
                            : 'Create your account',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _submitted
                            ? (_confirmationRequired
                                  ? 'Confirm your email using the link we sent, then sign in. If you already have an account, sign in instead.'
                                  : 'Your account is ready. Your gym administrator can now assign your workspace access.')
                            : 'Join your gym’s workspace with your own secure login.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (!_submitted) ...[
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.name],
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) => (value?.trim().isEmpty ?? true)
                              ? 'Enter your full name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _email,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Work email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Enter a valid email address',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            helperText: 'Use at least 12 characters',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => (value?.length ?? 0) < 12
                              ? 'Use at least 12 characters'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) {
                            if (!_busy) _submit();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) =>
                              value != _password.text ||
                                  (value?.isEmpty ?? true)
                              ? 'Passwords must match'
                              : null,
                        ),
                        const SizedBox(height: 24),
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
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Create account'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Creating an account does not grant gym access. Your gym administrator must assign your workspace and permissions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF657570),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _busy ? null : widget.onSignIn,
                        child: Text(
                          _submitted
                              ? 'Back to sign in'
                              : 'Already have an account? Sign in',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
