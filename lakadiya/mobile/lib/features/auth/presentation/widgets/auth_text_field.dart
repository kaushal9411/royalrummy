import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final Widget? suffix;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.suffix,
    this.prefix,
    this.keyboardType,
    this.validator,
    this.inputFormatters,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:       controller,
      obscureText:      obscure,
      keyboardType:     keyboardType,
      validator:        validator,
      inputFormatters:  inputFormatters,
      maxLength:        maxLength,
      decoration: InputDecoration(
        labelText:    label,
        hintText:     hint,
        suffixIcon:   suffix,
        prefix:       prefix,
        counterText:  maxLength != null ? '' : null,
      ),
    );
  }
}
