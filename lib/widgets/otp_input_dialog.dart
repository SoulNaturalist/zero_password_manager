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
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Требуется 2FA'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Введите 6-значный код из приложения аутентификации:'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '000000',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.button),
          child: const Text('Войти'),
        ),
      ],
    );
  }
}
