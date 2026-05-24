import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_text_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey  = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _passCtl  = TextEditingController();
  bool _obscure   = true;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  void _login() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
      AuthLoginRequested(_emailCtl.text.trim(), _passCtl.text),
    );
  }

  Future<void> _googleLogin() async {
    final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
    final account = await googleSignIn.signIn();
    if (account == null || !mounted) return;
    context.read<AuthBloc>().add(AuthGoogleRequested(
      account.id, account.email, account.displayName ?? account.email,
      avatarUrl: account.photoUrl,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (ctx, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: AppColors.danger),
            );
          }
        },
        builder: (ctx, state) {
          final loading = state is AuthLoading;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    // Logo / title
                    Text(
                      '♠ Lakadiya',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.accent,
                        fontSize: 40,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Callbreak Card Game',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 48),

                    AuthTextField(
                      controller: _emailCtl,
                      label:       'Email',
                      hint:        'your@email.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v == null || !v.contains('@') ? 'Enter valid email' : null,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _passCtl,
                      label:     'Password',
                      hint:      '••••••••',
                      obscure:   _obscure,
                      suffix: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) =>
                          v == null || v.length < 6 ? 'Min 6 characters' : null,
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: loading ? null : _login,
                      child: loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Login'),
                    ),
                    const SizedBox(height: 12),

                    // Google login
                    OutlinedButton.icon(
                      onPressed: loading ? null : _googleLogin,
                      icon: const Text('G', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.darkBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Guest
                    TextButton(
                      onPressed: loading ? null : () =>
                          context.read<AuthBloc>().add(AuthGuestRequested()),
                      child: const Text('Play as Guest'),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account? ",
                            style: Theme.of(context).textTheme.bodyMedium),
                        TextButton(
                          onPressed: () => context.go('/register'),
                          child: const Text('Register'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
