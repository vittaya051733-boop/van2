import 'package:flutter/material.dart';

class OmiseMobileBankOption {
  const OmiseMobileBankOption({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;
}

const List<OmiseMobileBankOption> kOmiseMobileBankOptions = <OmiseMobileBankOption>[
  OmiseMobileBankOption(code: 'kbank', label: 'กสิกรไทย (K PLUS)'),
  OmiseMobileBankOption(code: 'scb', label: 'ไทยพาณิชย์ (SCB Easy)'),
  OmiseMobileBankOption(code: 'bbl', label: 'กรุงเทพ (Bualuang mBanking)'),
  OmiseMobileBankOption(code: 'ktb', label: 'กรุงไทย (Krungthai NEXT)'),
  OmiseMobileBankOption(code: 'bay', label: 'กรุงศรี (KMA)'),
];

/// Lets the customer pick a mobile banking app before redirecting to Omise.
Future<String?> showOmiseMobileBankSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                'เลือกธนาคาร',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ระบบจะเปิดแอปธนาคารที่เลือกเพื่อยืนยันการชำระเงิน',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 12),
              for (final bank in kOmiseMobileBankOptions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(sheetContext).pop(bank.code),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.account_balance_outlined,
                              color: Color(0xFF374151),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                bank.label,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Color(0xFF9CA3AF),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
