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
            data: {'requires_password_setup': false},
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
      appBar: AppBar(actions: [ThemeSwitcher(), SizedBox(width: 12)]),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 42,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(height: 18),
                      Text(
                        'GymPro UAE',
                        style: Theme.of(context).textTheme.headlineLarge,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        recovery
                            ? 'Choose a new password'
                            : _reset
                                ? 'Reset your password'
                                : 'Welcome back. Let’s keep your gym moving.',
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 32),
                      if (!recovery)
                        TextFormField(
                          controller: _email,
                          autofillHints: [
                            _reset
                                ? AutofillHints.email
                                : AutofillHints.username
                          ],
                          keyboardType: _reset
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: _reset
                                ? 'Work email'
                                : 'Email, employee ID or username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (!_reset && value.isNotEmpty) return null;
                            return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(value)
                                ? null
                                : _reset
                                    ? 'Enter a valid email address'
                                    : 'Enter your email, employee ID or username';
                          },
                        ),
                      if (!_reset || recovery) ...[
                        SizedBox(height: 16),
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
                            prefixIcon: Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip:
                                  _obscure ? 'Show password' : 'Hide password',
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
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(_message!),
                        ),
                      SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? SizedBox(
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
                      SizedBox(height: 16),
                      if (!recovery &&
                          !_reset &&
                          widget.onCreateAccount != null)
                        OutlinedButton(
                          onPressed: _busy ? null : widget.onCreateAccount,
                          child: Text('Create account'),
                        ),
                      SizedBox(height: 16),
                      Text(
                        'Your workspace. Your team. A stronger community.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
