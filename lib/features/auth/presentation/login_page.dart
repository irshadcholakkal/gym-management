import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config.dart';
import '../../../core/theme.dart';
import '../data/auth_repository.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.repository,
    this.recoveryClient,
    this.onCreateAccount,
  });
  final AuthRepository repository;
  final SupabaseClient? recoveryClient;
  final VoidCallback? onCreateAccount;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false, _obscure = true, _reset = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (widget.recoveryClient != null) {
        await widget.recoveryClient!.auth.updateUser(
          UserAttributes(
            password: _password.text,
            data: const {'requires_password_setup': false},
          ),
        );
        await widget.repository.signOut();
      } else if (_reset) {
        await widget.repository.resetPassword(
          _email.text,
          AppConfig.redirect.isEmpty ? null : AppConfig.redirect,
        );
        if (mounted) {
          setState(
            () => _message =
                'If this email is registered, a reset link is on its way.',
          );
        }
      } else {
        await widget.repository.signIn(_email.text, _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Unable to connect. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = widget.recoveryClient != null;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
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
                      const SizedBox(height: 18),
                      Text(
                        'GymPro UAE',
                        style: Theme.of(context).textTheme.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recovery
                            ? 'Choose a new password'
                            : _reset
                            ? 'Reset your password'
                            : 'Welcome back. Let’s keep your gym moving.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      if (!recovery)
                        TextFormField(
                          controller: _email,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Work email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v?.trim() ?? '')
                              ? null
                              : 'Enter a valid email address',
                        ),
                      if (!_reset || recovery) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          onFieldSubmitted: (_) => _busy ? null : _submit(),
                          autofillHints: [
                            recovery
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Password',
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
                          validator: (v) =>
                              (v?.length ?? 0) < (recovery ? 12 : 1)
                              ? recovery
                                    ? 'Use at least 12 characters'
                                    : 'Enter your password'
                              : null,
                        ),
                      ],
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(_message!),
                        ),
                      const SizedBox(height: 24),
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
                            : Text(
                                recovery
                                    ? 'Save password'
                                    : _reset
                                    ? 'Send reset link'
                                    : 'Sign in',
                              ),
                      ),
                      if (!recovery)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _reset = !_reset;
                                  _message = null;
                                }),
                          child: Text(
                            _reset ? 'Back to sign in' : 'Forgot password?',
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (!recovery &&
                          !_reset &&
                          widget.onCreateAccount != null)
                        OutlinedButton(
                          onPressed: _busy ? null : widget.onCreateAccount,
                          child: const Text('Create account'),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your workspace. Your team. A stronger community.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF657570),
                          fontSize: 12,
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
    );
  }
}
