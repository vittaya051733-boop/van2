import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_contact_screen.dart';
import 'admin_support_thread_screen.dart';
import 'services/admin_support_config.dart';
import 'services/admin_support_service.dart';

class AdminSupportInboxScreen extends StatelessWidget {
  const AdminSupportInboxScreen({
    super.key,
    required this.config,
    this.accentColor = const Color(0xFFFF8A1E),
  });

  final AdminSupportConfig config;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        title: const Text(
          'ข้อความถึงแอดมิน',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'ส่งข้อความใหม่',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminContactScreen(
                    config: config,
                    accentColor: accentColor,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AdminContactScreen(
                config: config,
                accentColor: accentColor,
              ),
            ),
          );
        },
        icon: const Icon(Icons.support_agent_rounded),
        label: const Text('ติดต่อใหม่'),
      ),
      body: user == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : StreamBuilder<List<AdminSupportTicketSummary>>(
              stream: AdminSupportService.streamMyTickets(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('โหลดไม่สำเร็จ\n${snapshot.error}'),
                    ),
                  );
                }

                final tickets = snapshot.data ?? const <AdminSupportTicketSummary>[];
                if (tickets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.mark_chat_unread_outlined,
                            size: 56,
                            color: accentColor.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'ยังไม่มีข้อความ',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'กดปุ่มด้านล่างเพื่อส่งคำถามถึงแอดมิน',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ticket = tickets[index];
                    return _TicketTile(
                      ticket: ticket,
                      accentColor: accentColor,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AdminSupportThreadScreen(
                              ticketId: ticket.id,
                              accentColor: accentColor,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({
    required this.ticket,
    required this.accentColor,
    required this.onTap,
  });

  final AdminSupportTicketSummary ticket;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            ticket.topicLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (ticket.unreadForRequester)
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.previewText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _statusLabel(ticket.status),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'open' => 'รอแอดมินตอบ',
      'in_progress' => 'กำลังติดตาม',
      'resolved' => 'แก้ไขแล้ว',
      'closed' => 'ปิดเรื่อง',
      _ => status,
    };
  }
}
