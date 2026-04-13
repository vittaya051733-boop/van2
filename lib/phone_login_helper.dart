class PhoneLoginHelper {
  PhoneLoginHelper._();

  static String normalize(String input) {
    final cleaned = input.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
    if (cleaned.startsWith('0') && cleaned.length == 10) {
      return '+66${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('+')) {
      return cleaned;
    }
    if (RegExp(r'^\d{9,15}$').hasMatch(cleaned)) {
      return '+$cleaned';
    }
    return cleaned;
  }
}
