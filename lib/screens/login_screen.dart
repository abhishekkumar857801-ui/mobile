import 'package:flutter/material.dart';

import '../services/session.dart';
import '../widgets/common.dart';
import 'server_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await session.register(_name.text, _email.text, _password.text);
      } else {
        await session.login(_email.text, _password.text);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 12, 12, 40),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                BrandLogo(size: 40, onColor: true),
                SizedBox(width: 10),
                Text('TeamFlow', style: TextStyle(color: AppColors.cream, fontSize: 20, fontWeight: FontWeight.w700)),
                Spacer(),
                IconButton(
                  tooltip: 'Server settings',
                  color: AppColors.cream,
                  icon: Icon(Icons.dns_outlined),
                  onPressed: () => showServerDialog(context),
                ),
              ]),
              SizedBox(height: 28),
              Text(
                _register ? 'Join your team\nin seconds.' : 'Your team\'s work,\nthe same everywhere.',
                style: TextStyle(color: AppColors.cream, fontSize: 30, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.5),
              ),
              SizedBox(height: 10),
              Text(
                'Punch your tickets forward here; your manager sees it on the web the same second.',
                style: TextStyle(color: Color(0xE6F4EDE0), fontSize: 14),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_register ? 'Create your account' : 'Welcome back', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: 16),
                if (_error != null) ...[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                    child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                  SizedBox(height: 12),
                ],
                if (_register) ...[
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                  ),
                  SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  decoration: InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) => (v ?? '').length < (_register ? 6 : 1) ? (_register ? 'At least 6 characters' : 'Enter your password') : null,
                ),
                SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 16)),
                  child: _busy
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : Text(_register ? 'Create account' : 'Sign in'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _register = !_register;
                    _error = null;
                  }),
                  child: Text(_register ? 'Have an account? Sign in' : 'New here? Create an account'),
                ),

              ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }
}
