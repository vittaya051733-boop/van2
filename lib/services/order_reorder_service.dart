import 'package:cloud_firestore/cloud_firestore.dart';

import '../category_catalog_screen.dart';
import '../public_catalog_service.dart';

class OrderReorderLine {
  const OrderReorderLine({
    required this.productId,
    required this.quantity,
    required this.selectedToppings,
    this.fallbackName,
  });

  final String productId;
  final int quantity;
  final List<String> selectedToppings;
  final String? fallbackName;
}

class OrderReorderResult {
  const OrderReorderResult({
    required this.selections,
    required this.skippedNames,
    required this.messages,
  });

  final List<CartProductSelection> selections;
  final List<String> skippedNames;
  final List<String> messages;

  bool get hasSelections => selections.isNotEmpty;
}

class OrderReorderService {
  OrderReorderService._();

  static const Set<String> _skipProductIds = <String>{
    'travel_passenger_service',
  };

  static List<OrderReorderLine> readProductLines(Map<String, dynamic> orderData) {
    final rawProducts = orderData['products'] ?? orderData['items'];
    if (rawProducts is! List) {
      return const <OrderReorderLine>[];
    }

    final results = <OrderReorderLine>[];
    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }

      final productMap = Map<String, dynamic>.from(rawProduct);
      final productId = _readFirstNonEmptyValue(
        productMap,
        const <String>[
          'productId',
          'product_id',
          'id',
          'docId',
          'documentId',
        ],
      );
      if (productId == null ||
          productId.isEmpty ||
          _skipProductIds.contains(productId)) {
        continue;
      }

      final quantityRaw = productMap['quantity'];
      final quantity = quantityRaw is num
          ? quantityRaw.toInt()
          : int.tryParse('${quantityRaw ?? ''}'.trim()) ?? 1;
      final selectedToppings = _readSelectedToppings(productMap);
      final fallbackName = _readFirstNonEmptyValue(
        productMap,
        const <String>['name', 'productName', 'title'],
      );

      results.add(
        OrderReorderLine(
          productId: productId,
          quantity: quantity.clamp(1, 99),
          selectedToppings: selectedToppings,
          fallbackName: fallbackName,
        ),
      );
    }

    return results;
  }

  static Future<OrderReorderResult> buildSelectionsFromOrder(
    Map<String, dynamic> orderData,
  ) async {
    final lines = readProductLines(orderData);
    if (lines.isEmpty) {
      return const OrderReorderResult(
        selections: <CartProductSelection>[],
        skippedNames: <String>[],
        messages: <String>['ไม่พบสินค้าในออเดอร์นี้'],
      );
    }

    final productIds = lines.map((line) => line.productId).toList(growable: false);
    final resolved = await PublicCatalogService.resolveProductsByIds(
      productIds,
      requireDisplayImage: false,
    );
    final productById = <String, PublicCatalogProduct>{
      for (final product in resolved) product.id: product,
    };

    final selections = <CartProductSelection>[];
    final skippedNames = <String>[];
    final messages = <String>[];

    for (final line in lines) {
      final product = productById[line.productId];
      if (product == null) {
        skippedNames.add(line.fallbackName ?? line.productId);
        continue;
      }

      final selection = buildCartSelectionFromCatalogProduct(
        product: product,
        quantity: line.quantity,
        selectedToppingLabels: line.selectedToppings,
      );
      if (selection == null) {
        skippedNames.add(
          line.fallbackName ??
              (product.data['name'] ?? 'สินค้า').toString(),
        );
        continue;
      }

      selections.add(selection);
    }

    if (selections.isEmpty) {
      messages.add('สินค้าในออเดอร์นี้ไม่พร้อมขายแล้ว');
    } else if (skippedNames.isNotEmpty) {
      messages.add(
        'เพิ่ม ${selections.length} รายการแล้ว (บางรายการไม่พร้อมขาย)',
      );
    }

    return OrderReorderResult(
      selections: selections,
      skippedNames: skippedNames,
      messages: messages,
    );
  }

  static List<String> _readSelectedToppings(Map<String, dynamic> productMap) {
    const keys = <String>[
      'selectedToppings',
      'toppings',
      'topping',
      'addons',
      'addOns',
    ];
    for (final key in keys) {
      final raw = productMap[key];
      if (raw is! List) {
        continue;
      }
      final labels = raw
          .map((entry) {
            if (entry is Map) {
              return (entry['label'] ?? entry['name'] ?? entry['title'])
                  .toString()
                  .trim();
            }
            return entry.toString().trim();
          })
          .where((label) => label.isNotEmpty)
          .toList(growable: false);
      if (labels.isNotEmpty) {
        return labels;
      }
    }
    return const <String>[];
  }

  static String? _readFirstNonEmptyValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

bool isTravelPassengerOrderData(Map<String, dynamic> data) {
  final orderType = (data['orderType'] as String?)?.trim();
  final serviceType = (data['serviceType'] as String?)?.trim();
  return orderType == 'travel_passenger' || serviceType == 'travel_passenger';
}

Timestamp? readOrderHistoryTimestamp(Map<String, dynamic> data) {
  for (final field in <String>[
    'deliveredAt',
    'cancelledAt',
    'updatedAt',
    'createdAt',
  ]) {
    final value = data[field];
    if (value is Timestamp) {
      return value;
    }
  }
  return null;
}
