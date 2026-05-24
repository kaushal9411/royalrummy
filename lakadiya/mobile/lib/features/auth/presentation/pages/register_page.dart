import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_text_field.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtl    = TextEditingController();
  final _emailCtl   = TextEditingController();
  final _passCtl    = TextEditingController();
  final _confirmCtl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtl.dispose(); _emailCtl.dispose();
    _passCtl.dispose(); _confirmCtl.dispose();
    super.dispose();
  }

  void _register() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
      AuthRegisterRequested(
        _nameCtl.text.trim(),
        _emailCtl.text.trim(),
        _passCtl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
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
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthTextField(
                    controller: _nameCtl,
                    label: 'Username',
                    hint:  'coolplayer123',
                    validator: (v) {
                      if (v == null || v.length < 3) return 'Min 3 characters';
                      if (v.length > 30) return 'Max 30 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _emailCtl,
                    label: 'Email',
                    hint:  'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        v == null || !v.contains('@') ? 'Enter valid email' : null,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _passCtl,
                    label:   'Password',
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (v) =>
                        v == null || v.length < 6 ? 'Min 6 characters' : null,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _confirmCtl,
                    label:   'Confirm Password',
                    obscure: true,
                    validator: (v) =>
                        v != _passCtl.text ? 'Passwords do not match' : null,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: loading ? null : _register,
                    child: loading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Register'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account? ',
                          style: Theme.of(context).textTheme.bodyMedium),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Login'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
