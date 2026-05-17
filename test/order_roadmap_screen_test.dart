import 'package:cloud_firestore/cloud_firestore.dart';
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
        {'name': 'กาแฟเย็นหวานน้อยเพิ่มช็อต', 'quantity': 2},
        {'name': 'ชาไทยปั่นวิปครีม', 'quantity': 1},
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

  testWidgets(
    'roadmap card loads shop image from products collection when order has none',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('orders').doc('order-shop-image-1').set({
        'orderId': 'order-shop-image-1',
        'orderCode': 'ORD-SHOP-01',
        'status': 'pending',
        'shopName': 'ร้านมีรูปจากโปรดักส์',
        'shopId': 'shop-123',
        'grandTotal': 89.0,
        'products': [
          {'name': 'ข้าวไข่เจียว', 'quantity': 1, 'productId': 'product-123'},
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

      expect(
        find.byKey(const ValueKey<String>('roadmap-shop-image')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'roadmap card asks customer to wait or cancel when shop does not respond',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('orders').doc('order-shop-timeout-1').set({
        'orderId': 'order-shop-timeout-1',
        'orderCode': 'ORD-SHOP-TIMEOUT-01',
        'status': 'accepted',
        'shopName': 'ร้านยังไม่กดรับ',
        'driverId': 'rider-123',
        'acceptedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 16)),
        ),
        'grandTotal': 129.0,
        'products': [
          {'name': 'ข้าวกะเพรา', 'quantity': 1},
        ],
        'createdAt': DateTime.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: OrderRoadmapScreen(
            orderIds: const ['order-shop-timeout-1'],
            firestore: firestore,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('ร้านค้ายังไม่รับออเดอร์หลังไรเดอร์รับงานแล้ว'),
        findsOneWidget,
      );
      expect(find.text('รออีก 15 นาที'), findsOneWidget);
      expect(find.text('ยกเลิกออเดอร์'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel order asks for refund account and saves it on the order',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('orders').doc('order-shop-cancel-1').set({
        'orderId': 'order-shop-cancel-1',
        'orderCode': 'ORD-SHOP-CANCEL-01',
        'status': 'accepted',
        'shopName': 'ร้านยังไม่รับ',
        'driverId': 'rider-123',
        'acceptedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 16)),
        ),
        'grandTotal': 129.0,
        'products': [
          {'name': 'ข้าวกะเพรา', 'quantity': 1},
        ],
        'createdAt': DateTime.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: OrderRoadmapScreen(
            orderIds: const ['order-shop-cancel-1'],
            firestore: firestore,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('ยกเลิกออเดอร์'));
      await tester.pump();

      expect(find.text('ขอคืนเงิน'), findsOneWidget);
      expect(find.text('หมายเลขบัญชี'), findsOneWidget);
      expect(find.text('ชื่อเจ้าของบัญชี'), findsOneWidget);
      expect(find.text('ชื่อธนาคาร'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), '1234567890');
      await tester.enterText(find.byType(TextFormField).at(1), 'สมชาย ทดสอบ');
      await tester.enterText(find.byType(TextFormField).at(2), 'ธนาคารทดสอบ');
      await tester.ensureVisible(find.text('ยืนยันคืนเงิน'));
      await tester.tap(find.text('ยืนยันคืนเงิน'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final orderSnapshot = await firestore
          .collection('orders')
          .doc('order-shop-cancel-1')
          .get();
      final orderData = orderSnapshot.data()!;

      expect(orderData['status'], 'cancelled');
      expect(orderData['statusLabel'], 'ยกเลิกออเดอร์');
      expect(orderData['customerShopChoice'], 'cancel');
      expect(orderData['refundRequested'], true);
      expect(orderData['refundStatus'], 'requested');
      expect(orderData['refundBankAccountNumber'], '1234567890');
      expect(orderData['refundAccountName'], 'สมชาย ทดสอบ');
      expect(orderData['refundBankName'], 'ธนาคารทดสอบ');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'roadmap card asks customer to wait or cancel when shop rejects',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('orders').doc('order-shop-reject-1').set({
        'orderId': 'order-shop-reject-1',
        'orderCode': 'ORD-SHOP-REJECT-01',
        'status': 'accepted',
        'shopName': 'ร้านปฏิเสธ',
        'driverId': 'rider-123',
        'acceptedAt': Timestamp.fromDate(DateTime.now()),
        'shopDecisionStatus': 'rejected',
        'shopRejectedAt': Timestamp.fromDate(DateTime.now()),
        'grandTotal': 89.0,
        'products': [
          {'name': 'ชาเย็น', 'quantity': 1},
        ],
        'createdAt': DateTime.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: OrderRoadmapScreen(
            orderIds: const ['order-shop-reject-1'],
            firestore: firestore,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('ร้านค้าปฏิเสธออเดอร์นี้'), findsOneWidget);
      expect(find.text('รออีก 15 นาที'), findsOneWidget);
      expect(find.text('ยกเลิกออเดอร์'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
