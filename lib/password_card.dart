import 'package:flutter/material.dart';
import 'theme/colors.dart';

class PasswordCard extends StatelessWidget {
  final String service;
  final String emailOrUser;
  final String password;
  final String imageAsset;

  const PasswordCard({
    super.key,
    required this.service,
    required this.emailOrUser,
    required this.password,
    required this.imageAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Image.asset(imageAsset, width: 32, height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  emailOrUser,
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(password, style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white70),
            onPressed: () {
              // Clipboard logic
            },
          ),
        ],
      ),
    );
  }
}
