import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update({'status': newStatus});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus == 'accepted'
              ? 'รับออเดอร์เรียบร้อยแล้ว'
              : 'ปฏิเสธออเดอร์แล้ว'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('การแจ้งเตือน'),
        automaticallyImplyLeading: false,
      ),
      body: _currentUser == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบเพื่อดูการแจ้งเตือน'))
          : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('shopOwnerId', isEqualTo: _currentUser!.uid)
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('ยังไม่มีออเดอร์ใหม่', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                final orders = snapshot.data!.docs.toList();
                // Sort newest first on the client to avoid an extra Firestore composite index.
                orders.sort((a, b) {
                  final aTime = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  final bTime = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  return bTime.compareTo(aTime);
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final data = order.data() as Map<String, dynamic>;
                    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                    final formattedDate = timestamp != null
                        ? DateFormat('d MMM y, HH:mm', 'th').format(timestamp)
                        : 'ไม่มีข้อมูลเวลา';

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ออเดอร์ใหม่ #${order.id.substring(0, 6)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('เวลา: $formattedDate'),
                            Text('จำนวน: ${data['products']?.length ?? 0} รายการ'),
                            Text('ยอดรวม: ${data['totalPrice']?.toStringAsFixed(2) ?? 'N/A'} บาท'),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _updateOrderStatus(order.id, 'declined'),
                                  child: Text('ปฏิเสธ',
                                      style: TextStyle(
                                          color: Theme.of(context).colorScheme.error)),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _updateOrderStatus(order.id, 'accepted'),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('รับออเดอร์'),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
