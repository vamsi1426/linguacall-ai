import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Adds E.164 variants when the user dials the national number only (no country code).
/// [AuthService] stores [users.phone] as Firebase E.164 (e.g. +918008518191); the dialpad
/// often has 8008518191 — we infer +CC from the signed-in user's number.
void _addInferredE164Candidates(Set<String> candidates, String digits) {
  if (digits.isEmpty) return;

  var national = digits;
  if (national.startsWith('0')) {
    national = national.substring(1);
  }
  if (national != digits) {
    candidates.add(national);
    candidates.add('+$national');
  }

  final self = FirebaseAuth.instance.currentUser?.phoneNumber;
  if (self == null) return;

  final selfDigits = digitsOnly(self);
  if (national.length >= selfDigits.length) return;

  // Same country as this device: country-code length matches my E.164 minus national length.
  final ccLen = selfDigits.length - national.length;
  if (ccLen < 1 || ccLen > 4) return;

  final ccPart = selfDigits.substring(0, ccLen);
  if (!RegExp(r'^[1-9]\d*$').hasMatch(ccPart)) return;

  candidates.add('+$ccPart$national');
}

/// Resolves a Firestore user id from a phone string stored in [users.phone].
/// Realtime calls use this UID for Socket.io + WebRTC on any network (same as login identity).
Future<String?> findUidByPhone(String phone) async {
  final raw = phone.trim();
  if (raw.isEmpty) return null;

  final digits = digitsOnly(raw);
  final candidates = <String>{raw, digits, '+$digits'};
  _addInferredE164Candidates(candidates, digits);
  candidates.removeWhere((e) => e.isEmpty);

  final fs = FirebaseFirestore.instance;
  for (final key in candidates) {
    final q = await fs.collection('users').where('phone', isEqualTo: key).limit(1).get();
    if (q.docs.isNotEmpty) return q.docs.first.id;
  }
  return null;
}
