import 'package:flutter/material.dart';

bool orderIsCashOnDelivery(Map<String, dynamic> data) {
  final paymentMethod =
      (data['paymentMethod'] as String?)?.trim().toLowerCase() ?? '';
  final paymentStatus =
      (data['paymentStatus'] as String?)?.trim().toLowerCase() ?? '';
  return paymentMethod == 'cash_on_delivery' ||
      paymentStatus == 'cash_on_delivery';
}

bool orderCanRequestRefund(Map<String, dynamic> data) {
  if (orderIsCashOnDelivery(data)) {
    return false;
  }

  final paymentStatus =
      (data['paymentStatus'] as String?)?.trim().toLowerCase() ?? '';
  return paymentStatus == 'verified';
}

Future<Map<String, String>?> showOrderRefundAccountDialog(
  BuildContext context,
) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => const OrderRefundAccountDialog(),
  );
}

class OrderRefundAccountDialog extends StatefulWidget {
  const OrderRefundAccountDialog({super.key});

  @override
  State<OrderRefundAccountDialog> createState() => _OrderRefundAccountDialogState();
}

class _OrderRefundAccountDialogState extends State<OrderRefundAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _bankNameController = TextEditingController();

  @override
  void dispose() {
    _accountNumberController.dispose();
    _accountNameController.dispose();
    _bankNameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, {
      'refundBankAccountNumber': _accountNumberController.text.trim(),
      'refundAccountName': _accountNameController.text.trim(),
      'refundBankName': _bankNameController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ขอคืนเงิน'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'กรุณาใส่หมายเลขบัญชี ชื่อ และธนาคารให้ถูกต้อง และต้องเป็นบัญชีที่โอนมาซื้อเท่านั้น หากเป็นบัญชีอื่นจะไม่สามารถโอนคืนได้ เนื่องจากเกี่ยวข้องกับข้อกฎหมาย ระบบสรุปยอดเวลา 18:00 น. ของทุกวัน และเงินจะเข้าบัญชีช่วง 18:00-20:00 น.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'หมายเลขบัญชี',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'กรุณาใส่หมายเลขบัญชี';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อเจ้าของบัญชี',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'กรุณาใส่ชื่อเจ้าของบัญชี';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankNameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อธนาคาร',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'กรุณาใส่ชื่อธนาคาร';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _submit, child: const Text('ยืนยันคืนเงิน')),
      ],
    );
  }
}
