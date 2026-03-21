import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:linguacall/screens/call/outgoing_call_screen.dart';
import 'package:linguacall/services/auth_service.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/utils/theme.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthService, String?>((s) => s.user?.uid);

    return Scaffold(
      body: uid == null
          ? const Center(child: Text('Please login to see call history.'))
          : StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('calls')
                  .where('participantsUids', arrayContains: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _EmptyState(
                    onSimulateOutgoing: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OutgoingCallScreen(
                            targetPhone: '+1 999 999 9999',
                            callType: CallType.voice,
                          ),
                        ),
                      );
                    },
                  );
                }

                final calls = docs
                    .map((d) => d.data())
                    .whereType<Map<String, dynamic>>()
                    .toList();

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: calls.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = calls[index];
                    final status = (data['status'] ?? 'unknown').toString();
                    final direction = (data['direction'] ?? '').toString();
                    final callTypeStr = (data['callType'] ?? 'voice').toString();
                    final callType = callTypeStr == 'video' ? CallType.video : CallType.voice;

                    final otherPhone = direction == 'outgoing'
                        ? (data['toPhone'] ?? '').toString()
                        : (data['fromPhone'] ?? '').toString();

                    return GlassCallCard(
                      title: otherPhone.isEmpty ? 'Unknown number' : otherPhone,
                      subtitle: '${direction.capitalize()} • ${callType.name} • $status',
                      status: status,
                      onCallBack: otherPhone.isEmpty
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OutgoingCallScreen(
                                    targetPhone: otherPhone,
                                    callType: callType,
                                  ),
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

class GlassCallCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback? onCallBack;

  const GlassCallCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onCallBack,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = status == 'connected'
        ? AppTheme.secondaryColor
        : status == 'ended'
            ? Colors.white54
            : status == 'ringing' || status == 'calling'
                ? Colors.orangeAccent
                : AppTheme.textMuted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0038F5), Color(0xFF9F03FF)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.call, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              IconButton(
                icon: const Icon(Icons.phone, color: AppTheme.secondaryColor),
                onPressed: onCallBack,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onSimulateOutgoing;
  const _EmptyState({required this.onSimulateOutgoing});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 64, color: AppTheme.secondaryColor),
            const SizedBox(height: 16),
            const Text(
              'No call history yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start a simulated outgoing call to populate Firestore.',
              style: TextStyle(color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onSimulateOutgoing,
              child: const Text('Simulate Call'),
            )
          ],
        ),
      ),
    );
  }
}

extension _StringCaps on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
