import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:linguacall/screens/call/outgoing_call_screen.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/utils/theme.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      body: uid == null
          ? const Center(child: Text('Please login to view contacts.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('contacts')
                  .where('ownerUid', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const _EmptyContacts();
                }

                final docs = snapshot.data!.docs;
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final contact = docs[index].data();
                    final contactUid = (contact['contactUid'] ?? '').toString();
                    final phone = (contact['phone'] ?? '').toString();
                    final name = (contact['name'] ?? '').toString();

                    return GlassContactCard(
                      name: name.isEmpty ? 'Unknown' : name,
                      phone: phone,
                      onlineStream: contactUid.isEmpty
                          ? null
                          : FirebaseFirestore.instance
                              .collection('users')
                              .doc(contactUid)
                              .snapshots(),
                      onCallVoice: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OutgoingCallScreen(
                              targetPhone: phone,
                              callType: CallType.voice,
                            ),
                          ),
                        );
                      },
                      onCallVideo: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OutgoingCallScreen(
                              targetPhone: phone,
                              callType: CallType.video,
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

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add, size: 64, color: AppTheme.secondaryColor),
            SizedBox(height: 16),
            Text(
              'No contacts yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Use the Dialpad to save numbers into Firestore.',
              style: TextStyle(color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class GlassContactCard extends StatelessWidget {
  final String name;
  final String phone;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? onlineStream;
  final VoidCallback onCallVoice;
  final VoidCallback onCallVideo;

  const GlassContactCard({
    super.key,
    required this.name,
    required this.phone,
    required this.onlineStream,
    required this.onCallVoice,
    required this.onCallVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassCard,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0038F5), Color(0xFF9F03FF)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onlineStream == null)
                const Text(
                  'Offline',
                  style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 12),
                )
              else
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: onlineStream,
                  builder: (context, snapshot) {
                    final online = snapshot.data?.data()?['onlineStatus'] == true;
                    return Text(
                      online ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: online ? AppTheme.secondaryColor : Colors.white54,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.call, color: AppTheme.secondaryColor),
                    onPressed: onCallVoice,
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam, color: AppTheme.secondaryColor),
                    onPressed: onCallVideo,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

