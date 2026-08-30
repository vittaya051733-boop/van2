import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/locale_service.dart';

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
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
        return AlertDialog(
          title: Text(L10n.refundDialogTitle),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.refundDialogBody,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountNumberController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: L10n.accountNumberLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return L10n.accountNumberRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountNameController,
                    decoration: InputDecoration(
                      labelText: L10n.accountHolderName,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return L10n.accountHolderRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bankNameController,
                    decoration: InputDecoration(
                      labelText: L10n.bankNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return L10n.bankNameRequired;
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
              child: Text(L10n.cancel),
            ),
            FilledButton(
              onPressed: _submit,
              child: Text(L10n.confirmRefund),
            ),
          ],
        );
      },
    );
  }
}
