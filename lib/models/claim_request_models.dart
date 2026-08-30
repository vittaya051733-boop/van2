class ClaimRequestItem {
  const ClaimRequestItem({
    required this.productId,
    required this.name,
    required this.quantity,
    this.unitPrice,
    this.imageUrl,
  });

  final String productId;
  final String name;
  final int quantity;
  final double? unitPrice;
  final String? imageUrl;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'productId': productId,
      if (name.isNotEmpty) 'name': name,
      'quantity': quantity,
      if (unitPrice != null) 'unitPrice': unitPrice,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty) 'imageUrl': imageUrl,
    };
  }

  factory ClaimRequestItem.fromMap(Map<dynamic, dynamic> raw) {
    return ClaimRequestItem(
      productId: _readString(raw['productId']) ?? '',
      name: _readString(raw['name']) ?? 'สินค้า',
      quantity: _readInt(raw['quantity']) ?? 1,
      unitPrice: _readDouble(raw['unitPrice']),
      imageUrl: _readString(raw['imageUrl']),
    );
  }
}

class ClaimRequestPayload {
  const ClaimRequestPayload({
    required this.items,
    required this.reason,
    this.status = 'pending',
    this.claimId,
  });

  static const String topicKey = 'product_claim';
  static const String topicLabel = 'ขอเคลมสินค้า';

  final List<ClaimRequestItem> items;
  final String reason;
  final String status;
  final String? claimId;

  bool get isPending => status == 'pending';

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'items': items.map((item) => item.toMap()).toList(growable: false),
      'reason': reason,
      'status': status,
      if (claimId != null && claimId!.trim().isNotEmpty) 'claimId': claimId,
    };
  }

  factory ClaimRequestPayload.fromMap(Map<dynamic, dynamic> raw) {
    final rawItems = raw['items'];
    final items = <ClaimRequestItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          items.add(ClaimRequestItem.fromMap(entry));
        }
      }
    }
    return ClaimRequestPayload(
      items: items,
      reason: _readString(raw['reason']) ?? 'other',
      status: _readString(raw['status']) ?? 'pending',
      claimId: _readString(raw['claimId']),
    );
  }

  static String reasonLabel(String reason) {
    switch (reason) {
      case 'mismatch':
        return 'ไม่ตรงปก';
      case 'damaged':
        return 'เสียหาย';
      case 'wrong_item':
        return 'ส่งผิดชิ้น';
      case 'other':
        return 'อื่น ๆ';
      default:
        return reason;
    }
  }

  String buildSummaryMessage({String? extraNote}) {
    final buffer = StringBuffer('ขอเคลมสินค้า — ${reasonLabel(reason)}\n');
    for (final item in items) {
      buffer.writeln('- ${item.name} x${item.quantity}');
    }
    final note = extraNote?.trim();
    if (note != null && note.isNotEmpty) {
      buffer.writeln('\nหมายเหตุ: $note');
    }
    return buffer.toString().trim();
  }
}

String? _readString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}
