import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum CallPhase { idle, calling, ringing, connecting, connected, ended }

enum CallType { voice, video }

class CallStateService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CallPhase _phase = CallPhase.idle;
  CallType _callType = CallType.voice;

  String? _callId;
  String? _targetPhone;
  bool _isOutgoing = true;

  /// Firebase uid of the remote peer when using realtime signaling + WebRTC.
  String? _peerUid;
  String? get peerUid => _peerUid;

  /// True after WebRTC data channel is ready to carry translated audio.
  bool _webrtcMediaReady = false;
  bool get webrtcMediaReady => _webrtcMediaReady;

  Timer? _connectTimer;
  Timer? _endTimer;

  CallPhase get phase => _phase;
  CallType get callType => _callType;
  String? get callId => _callId;
  String? get targetPhone => _targetPhone;
  bool get isOutgoing => _isOutgoing;

  void _cancelTimers() {
    _connectTimer?.cancel();
    _endTimer?.cancel();
    _connectTimer = null;
    _endTimer = null;
  }

  Future<void> startOutgoingCall({
    required String targetPhone,
    required CallType callType,
    bool simulateConnection = true,
    String? peerUid,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _cancelTimers();

    _isOutgoing = true;
    _callType = callType;
    _targetPhone = targetPhone;
    _peerUid = peerUid;
    _webrtcMediaReady = false;
    _phase = CallPhase.calling;
    notifyListeners();

    try {
      final fromPhone = currentUser.phoneNumber ?? '';
      final participantsUids = peerUid != null
          ? <String>[currentUser.uid, peerUid]
          : <String>[currentUser.uid];

      final callRef = _firestore.collection('calls').doc();
      _callId = callRef.id;

      await callRef.set({
        'participantsUids': participantsUids,
        'direction': 'outgoing',
        'callType': callType.name, // 'voice' | 'video'
        'status': _phase.name, // 'calling'
        'fromPhone': fromPhone,
        'toPhone': targetPhone,
        if (peerUid != null) 'peerUid': peerUid,
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (simulateConnection) {
        // Demo: calling -> connected (unchanged legacy behavior).
        _connectTimer = Timer(const Duration(seconds: 4), () async {
          _phase = CallPhase.connected;
          notifyListeners();
          if (_callId == null) return;
          await _firestore.collection('calls').doc(_callId).update({
            'status': _phase.name,
            'connectedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      }
    } catch (e) {
      debugPrint('startOutgoingCall failed: $e');
      await endCall(reason: 'error');
    }
  }

  Future<void> startIncomingCall({
    required String fromPhone,
    required CallType callType,
    String? peerUid,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _cancelTimers();

    _isOutgoing = false;
    _callType = callType;
    _targetPhone = fromPhone; // show who is calling
    _peerUid = peerUid;
    _webrtcMediaReady = false;
    _phase = CallPhase.ringing;
    notifyListeners();

    try {
      final participantsUids = peerUid != null
          ? <String>[currentUser.uid, peerUid]
          : <String>[currentUser.uid];

      final callRef = _firestore.collection('calls').doc();
      _callId = callRef.id;

      await callRef.set({
        'participantsUids': participantsUids,
        'direction': 'incoming',
        'callType': callType.name,
        'status': _phase.name, // 'ringing'
        'fromPhone': fromPhone,
        'toPhone': currentUser.phoneNumber ?? '',
        if (peerUid != null) 'peerUid': peerUid,
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('startIncomingCall failed: $e');
      await endCall(reason: 'error');
    }
  }

  Future<void> acceptIncomingCall({bool realtime = false}) async {
    if (_phase != CallPhase.ringing) return;

    _cancelTimers();
    _phase = realtime ? CallPhase.connecting : CallPhase.connected;
    notifyListeners();

    if (_callId != null) {
      await _firestore.collection('calls').doc(_callId).update({
        'status': _phase.name,
        if (!realtime) 'connectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Realtime: [markConnectedFromRealtime] sets connected + connectedAt.
  }

  /// WebRTC negotiation in progress (signaling accepted, waiting for media path).
  void markConnecting() {
    if (_phase == CallPhase.calling || _phase == CallPhase.ringing) {
      _phase = CallPhase.connecting;
      notifyListeners();
    }
  }

  /// Called when translated audio can flow (data channel open).
  Future<void> markConnectedFromRealtime() async {
    _cancelTimers();
    _webrtcMediaReady = true;
    _phase = CallPhase.connected;
    notifyListeners();

    if (_callId != null) {
      await _firestore.collection('calls').doc(_callId).update({
        'status': _phase.name,
        'connectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> rejectIncomingCall() async {
    if (_phase != CallPhase.ringing) return;
    await endCall(reason: 'rejected');
  }

  Future<void> endCall({required String reason}) async {
    _cancelTimers();
    _webrtcMediaReady = false;
    _peerUid = null;
    _phase = CallPhase.ended;
    notifyListeners();

    final id = _callId;
    _callId = _callId; // keep for update
    try {
      if (id != null) {
        await _firestore.collection('calls').doc(id).update({
          'status': _phase.name,
          'endedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'endReason': reason,
        });
      }
    } catch (e) {
      debugPrint('endCall update failed: $e');
    }
  }

  void reset() {
    _cancelTimers();
    _phase = CallPhase.idle;
    _callId = null;
    _targetPhone = null;
    _peerUid = null;
    _webrtcMediaReady = false;
    _isOutgoing = true;
    _callType = CallType.voice;
    notifyListeners();
  }
}

