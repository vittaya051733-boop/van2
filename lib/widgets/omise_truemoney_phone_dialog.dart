import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Prompts for the TrueMoney Wallet phone number (10 digits, Thai format).
Future<String?> showOmiseTrueMoneyPhoneDialog({
  required BuildContext context,
  String? initialPhone,
}) {
  final authPhone = FirebaseAuth.instance.currentUser?.phoneNumber;
  final seed = _normalizeThaiPhone(initialPhone ?? authPhone ?? '');

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return _OmiseTrueMoneyPhoneDialog(initialPhone: seed);
    },
  );
}

String _normalizeThaiPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10 && digits.startsWith('0')) {
    return digits;
  }
  if (digits.length == 11 && digits.startsWith('66')) {
    return '0${digits.substring(2)}';
  }
  if (digits.length == 9 && !digits.startsWith('0')) {
    return '0$digits';
  }
  return raw.replaceAll(RegExp(r'\D'), '');
}

class _OmiseTrueMoneyPhoneDialog extends StatefulWidget {
  const _OmiseTrueMoneyPhoneDialog({required this.initialPhone});

  final String initialPhone;

  @override
  State<_OmiseTrueMoneyPhoneDialog> createState() =>
      _OmiseTrueMoneyPhoneDialogState();
}

class _OmiseTrueMoneyPhoneDialogState extends State<_OmiseTrueMoneyPhoneDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = _normalizeThaiPhone(_controller.text.trim());
    if (phone.length != 10 || !phone.startsWith('0')) {
      setState(() => _errorText = 'กรุณากรอกเบอร์มือถือ 10 หลัก (เช่น 0812345678)');
      return;
    }
    Navigator.of(context).pop(phone);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เบอร์ TrueMoney Wallet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'กรอกเบอร์ที่ผูกกับ TrueMoney Wallet เพื่อรับ OTP และยืนยันการชำระเงิน',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: 'เบอร์มือถือ',
              hintText: '0812345678',
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ดำเนินการต่อ'),
        ),
      ],
    );
  }
}
