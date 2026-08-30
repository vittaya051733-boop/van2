import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'l10n/l10n.dart';
import 'services/locale_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const String _targetApp = 'van2';
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
              ? L10n.orderAcceptedSnack
              : L10n.orderRejectedSnack),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.errorOccurred(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _markAppNotificationRead(String id) async {
    await FirebaseFirestore.instance.collection('app_notifications').doc(id).set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(L10n.alertsTitle),
            automaticallyImplyLeading: false,
          ),
          body: _currentUser == null
              ? Center(child: Text(L10n.signInForAlerts))
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                      return Center(
                        child: Text(L10n.errorOccurred(snapshot.error!)),
                      );
                    }
                    final orders = (snapshot.data?.docs ??
                            <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                        .toList(growable: false);

                    orders.sort((a, b) {
                      final aTime =
                          (a.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ??
                              0;
                      final bTime =
                          (b.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ??
                              0;
                      return bTime.compareTo(aTime);
                    });

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('app_notifications')
                          .where('targetApp', isEqualTo: _targetApp)
                          .where('recipientUid', isEqualTo: _currentUser!.uid)
                          .where('read', isEqualTo: false)
                          .snapshots(),
                      builder: (context, notifSnapshot) {
                        final notifs = (notifSnapshot.data?.docs ??
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                            .toList(growable: false);

                        notifs.sort((a, b) {
                          final aTime = (a.data()['createdAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ??
                              0;
                          final bTime = (b.data()['createdAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ??
                              0;
                          return bTime.compareTo(aTime);
                        });

                        if (orders.isEmpty && notifs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notifications_off_outlined,
                                    size: 80, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(L10n.noAlertsYet,
                                    style: const TextStyle(
                                        fontSize: 18, color: Colors.grey)),
                              ],
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            for (final n in notifs)
                              Card(
                                elevation: 2,
                                margin: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: const Icon(Icons.campaign_outlined,
                                      color: Colors.orange),
                                  title: Text((n.data()['title'] as String?) ??
                                      L10n.alertFallbackTitle),
                                  subtitle:
                                      Text((n.data()['body'] as String?) ?? '-'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.done),
                                    onPressed: () =>
                                        _markAppNotificationRead(n.id),
                                  ),
                                ),
                              ),
                            for (final order in orders) _buildOrderCard(order),
                          ],
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildOrderCard(QueryDocumentSnapshot<Map<String, dynamic>> order) {
    final data = order.data();
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final locale = LocaleService.instance.isEnglish ? 'en' : 'th';
    final formattedDate = timestamp != null
        ? DateFormat('d MMM y, HH:mm', locale).format(timestamp)
        : L10n.noTimeData;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.newOrderNumber(order.id.substring(0, 6)),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('${L10n.orderTimeLabel}: $formattedDate'),
            Text(L10n.itemCountLabel(data['products']?.length ?? 0)),
            Text(L10n.totalAmountBaht(
                data['totalPrice']?.toStringAsFixed(2) ?? 'N/A')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _updateOrderStatus(order.id, 'declined'),
                  child: Text(L10n.reject,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _updateOrderStatus(order.id, 'accepted'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(L10n.acceptOrder),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
