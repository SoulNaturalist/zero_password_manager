import 'package:flutter/material.dart';
import 'theme/colors.dart';

class CustomInput extends StatelessWidget {
  final String hintText;
  final bool isPassword;

  const CustomInput({
    super.key,
    required this.hintText,
    this.isPassword = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      obscureText: isPassword,
      style: TextStyle(color: AppColors.text),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.white60),
        filled: true,
        fillColor: AppColors.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
