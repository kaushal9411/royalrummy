import 'package:flutter/material.dart';

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:    controller,
      obscureText:   obscure,
      keyboardType:  keyboardType,
      validator:     validator,
      decoration: InputDecoration(
        labelText:    label,
        hintText:     hint,
        suffixIcon:   suffix,
      ),
    );
  }
}
