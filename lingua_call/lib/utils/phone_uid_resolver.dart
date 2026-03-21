import 'package:cloud_firestore/cloud_firestore.dart';

String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Resolves a Firestore user id from a phone string stored in [users.phone].
/// Realtime calls use this UID for Socket.io + WebRTC on any network (same as login identity).
Future<String?> findUidByPhone(String phone) async {
  final raw = phone.trim();
  if (raw.isEmpty) return null;

  final digits = digitsOnly(raw);
  final candidates = <String>{raw, digits, '+$digits'};
  candidates.removeWhere((e) => e.isEmpty);

  final fs = FirebaseFirestore.instance;
  for (final key in candidates) {
    final q = await fs.collection('users').where('phone', isEqualTo: key).limit(1).get();
    if (q.docs.isNotEmpty) return q.docs.first.id;
  }
  return null;
}
