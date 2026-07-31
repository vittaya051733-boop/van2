enum OmisePaymentChannel {
  promptPay('omise_promptpay', 'พร้อมเพย์', 'assets/payment_logos/promptpay.png'),
  card('omise_card', 'บัตรเครดิต/เดบิต', 'assets/payment_logos/visa.png'),
  mobileBanking(
    'omise_mobile_banking',
    'Mobile Banking',
    'assets/payment_logos/mobile_banking.png',
  ),
  trueMoney('omise_truemoney', 'TrueMoney', 'assets/payment_logos/truemoney.png');

  const OmisePaymentChannel(this.methodId, this.label, this.logoAsset);

  final String methodId;
  final String label;
  final String logoAsset;

  /// Logos shown on each payment option row (matches banner strip).
  List<String> get tileLogoAssets {
    switch (this) {
      case OmisePaymentChannel.card:
        return const <String>[
          'assets/payment_logos/visa.png',
          'assets/payment_logos/mastercard.png',
          'assets/payment_logos/jcb.png',
        ];
      default:
        return <String>[logoAsset];
    }
  }

  String get paymentMethodLabel {
    switch (this) {
      case OmisePaymentChannel.promptPay:
        return 'พร้อมเพย์';
      case OmisePaymentChannel.card:
        return 'บัตรเครดิต/เดบิต';
      case OmisePaymentChannel.mobileBanking:
        return 'Mobile Banking';
      case OmisePaymentChannel.trueMoney:
        return 'TrueMoney';
    }
  }
}
