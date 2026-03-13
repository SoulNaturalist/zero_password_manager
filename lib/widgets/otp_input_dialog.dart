import 'package:flutter/material.dart';
import '../theme/colors.dart';

class OTPInputDialog extends StatefulWidget {
  const OTPInputDialog({super.key});

  @override
  State<OTPInputDialog> createState() => _OTPInputDialogState();
}

class _OTPInputDialogState extends State<OTPInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.input,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.security, color: AppColors.button),
          const SizedBox(width: 12),
          const Text('Защита 2FA', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Введите 6-значный код безопасности для подтверждения действия.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            maxLength: 6,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.button.withOpacity(0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.button.withOpacity(0.1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.button, width: 2),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.button,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('Подтвердить'),
        ),
      ],
    );
  }
}
