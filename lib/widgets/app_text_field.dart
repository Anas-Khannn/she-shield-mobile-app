import 'package:flutter/material.dart';
import 'package:she_shield/utils/app_colors.dart';

/// A reusable styled text field that uses the app's input decoration theme
/// with optional password-visibility toggle and accessible semantics.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.enabled = true,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final bool enabled;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: TextFormField(
        controller: widget.controller,
        obscureText: widget.obscureText && !_showPassword,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        enabled: widget.enabled,
        enableSuggestions: !widget.obscureText,
        autocorrect: !widget.obscureText,
        autofillHints: widget.autofillHints,
        validator: widget.validator,
        onFieldSubmitted: widget.onFieldSubmitted,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: widget.icon != null
              ? Icon(widget.icon, color: AppColors.accent)
              : null,
          suffixIcon: widget.obscureText
              ? IconButton(
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                )
              : null,
        ),
      ),
    );
  }
}