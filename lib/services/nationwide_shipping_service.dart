import '../cart_screen.dart';

class NationwideDeliveryAddress {
  const NationwideDeliveryAddress({
    required this.recipientName,
    required this.phoneNumber,
    required this.addressLine,
    required this.subDistrict,
    required this.district,
    required this.province,
    required this.postalCode,
    this.latitude,
    this.longitude,
    this.formattedAddress,
  });

  final String recipientName;
  final String phoneNumber;
  final String addressLine;
  final String subDistrict;
  final String district;
  final String province;
  final String postalCode;
  final double? latitude;
  final double? longitude;
  final String? formattedAddress;

  String get label =>
      '$addressLine $subDistrict $district $province $postalCode'.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'recipientName': recipientName,
    'phoneNumber': phoneNumber,
    'addressLine': addressLine,
    'subDistrict': subDistrict,
    'district': district,
    'province': province,
    'postalCode': postalCode,
    'label': label,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (formattedAddress?.trim().isNotEmpty == true)
      'formattedAddress': formattedAddress!.trim(),
  };
}

class NationwideParcelSummary {
  const NationwideParcelSummary({
    required this.totalWeightGrams,
    required this.totalQuantity,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
  });

  final int totalWeightGrams;
  final int totalQuantity;
  final double lengthCm;
  final double widthCm;
  final double heightCm;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'totalWeightGrams': totalWeightGrams,
    'totalQuantity': totalQuantity,
    'lengthCm': lengthCm,
    'widthCm': widthCm,
    'heightCm': heightCm,
  };
}

class NationwideShippingQuote {
  const NationwideShippingQuote({
    required this.provider,
    required this.providerLabel,
    required this.serviceLevel,
    required this.shippingFee,
    required this.parcel,
    required this.isManualEstimate,
  });

  final String provider;
  final String providerLabel;
  final String serviceLevel;
  final double shippingFee;
  final NationwideParcelSummary parcel;
  final bool isManualEstimate;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'provider': provider,
    'providerLabel': providerLabel,
    'serviceLevel': serviceLevel,
    'shippingFee': shippingFee,
    'isManualEstimate': isManualEstimate,
    'parcel': parcel.toJson(),
  };
}

class NationwideShippingService {
  const NationwideShippingService();

  NationwideShippingQuote estimateManualQuote({
    required List<CartLineItem> items,
    required NationwideDeliveryAddress address,
  }) {
    final parcel = summarizeParcel(items);
    final weightKg = (parcel.totalWeightGrams / 1000).ceil().clamp(1, 30);
    final remoteAreaSurcharge = _looksRemotePostalCode(address.postalCode)
        ? 30
        : 0;
    final fee = 45 + (weightKg * 18) + remoteAreaSurcharge;

    return NationwideShippingQuote(
      provider: 'manual',
      providerLabel: 'รอเชื่อมต่อ ShipPop',
      serviceLevel: 'manual_standard',
      shippingFee: fee.toDouble(),
      parcel: parcel,
      isManualEstimate: true,
    );
  }

  NationwideParcelSummary summarizeParcel(List<CartLineItem> items) {
    final totalQuantity = items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );
    final totalWeightGrams = items.fold<int>(
      0,
      (total, item) => total + (item.parcelWeightGrams * item.quantity),
    );

    return NationwideParcelSummary(
      totalWeightGrams: totalWeightGrams <= 0
          ? totalQuantity * 1000
          : totalWeightGrams,
      totalQuantity: totalQuantity,
      lengthCm: _maxDimension(items, (item) => item.parcelLengthCm) ?? 20,
      widthCm: _maxDimension(items, (item) => item.parcelWidthCm) ?? 15,
      heightCm: _maxDimension(items, (item) => item.parcelHeightCm) ?? 10,
    );
  }

  double? _maxDimension(
    List<CartLineItem> items,
    double? Function(CartLineItem item) readValue,
  ) {
    double? maxValue;
    for (final item in items) {
      final value = readValue(item);
      if (value == null || value <= 0) {
        continue;
      }
      if (maxValue == null || value > maxValue) {
        maxValue = value;
      }
    }
    return maxValue;
  }

  bool _looksRemotePostalCode(String postalCode) {
    final normalized = postalCode.trim();
    return normalized.startsWith('58') ||
        normalized.startsWith('95') ||
        normalized.startsWith('96');
  }
}
