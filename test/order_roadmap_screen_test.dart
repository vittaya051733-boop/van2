import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:van2/order_roadmap_screen.dart';

void main() {
  testWidgets('roadmap card stays readable on a small screen', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('orders').doc('order-small-1').set({
      'orderId': 'order-small-1',
      'orderCode': 'ORD-TEST-01',
      'status': 'pending',
      'shopName': 'ร้านทดสอบจอเล็ก',
      'grandTotal': 159.0,
      'products': [
        {
          'name': 'กาแฟเย็นหวานน้อยเพิ่มช็อต',
          'quantity': 2,
        },
        {
          'name': 'ชาไทยปั่นวิปครีม',
          'quantity': 1,
        },
      ],
      'createdAt': DateTime.now(),
    });

    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: OrderRoadmapScreen(
          orderIds: const ['order-small-1'],
          firestore: firestore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('สินค้าในออเดอร์'), findsOneWidget);
    expect(find.text('กาแฟเย็นหวานน้อยเพิ่มช็อต'), findsOneWidget);
    expect(find.text('2 ชิ้น'), findsOneWidget);
    expect(find.text('1 ชิ้น'), findsOneWidget);
    expect(find.textContaining('Order ID: order-small-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('roadmap card loads shop image from products collection when order has none', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('orders').doc('order-shop-image-1').set({
      'orderId': 'order-shop-image-1',
      'orderCode': 'ORD-SHOP-01',
      'status': 'pending',
      'shopName': 'ร้านมีรูปจากโปรดักส์',
      'shopId': 'shop-123',
      'grandTotal': 89.0,
      'products': [
        {
          'name': 'ข้าวไข่เจียว',
          'quantity': 1,
          'productId': 'product-123',
        },
      ],
      'createdAt': DateTime.now(),
    });
    await firestore.collection('products').doc('product-123').set({
      'shopId': 'shop-123',
      'shopImageUrl': 'https://example.com/shop-123.jpg',
      'isActive': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: OrderRoadmapScreen(
          orderIds: const ['order-shop-image-1'],
          firestore: firestore,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey<String>('roadmap-shop-image')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}