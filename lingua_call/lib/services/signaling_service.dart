import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:linguacall/config/app_config.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// Socket.io may deliver an event payload as a [Map] or as a single-element [List] (server/version dependent).
Map<String, dynamic>? _socketPayloadAsMap(dynamic data) {
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  if (data is List && data.isNotEmpty && data.first is Map) {
    return Map<String, dynamic>.from(data.first as Map);
  }
  return null;
}

class SignalingService extends ChangeNotifier {
  IO.Socket? socket;

  /// Defaults from [AppConfig]; can be reassigned before [connectAndRegister].
  String signalingUrl = AppConfig.signalingHttpUrl;

  String currentUid = '';

  Function(Map<String, dynamic>)? onIncomingCall;
  Function(Map<String, dynamic>)? onCallAccepted;
  Function(Map<String, dynamic>)? onCallRejected;
  Function(Map<String, dynamic>)? onCallFailed;
  Function(Map<String, dynamic>)? onOffer;
  Function(Map<String, dynamic>)? onAnswer;
  Function(Map<String, dynamic>)? onRemoteIceCandidate;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  /// Waits until Socket.io is connected and `register-user` can run, or [timeout] elapses.
  /// Avoids the outgoing-call race where the first frame runs before [onConnect].
  Future<bool> waitForConnection({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_isConnected) return true;

    final completer = Completer<bool>();
    Timer? timer;

    void listener() {
      if (_isConnected && !completer.isCompleted) {
        timer?.cancel();
        removeListener(listener);
        completer.complete(true);
      }
    }

    addListener(listener);
    timer = Timer(timeout, () {
      removeListener(listener);
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  void connectAndRegister(String uid) {
    currentUid = uid;

    socket?.dispose();
    socket = IO.io(signalingUrl, <String, dynamic>{
      // Polling fallback helps some mobile carriers / proxies where websocket-only fails.
      'transports': <String>['websocket', 'polling'],
      'reconnection': true,
      'reconnectionAttempts': 20,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'timeout': 10000,
      'autoConnect': true,
    });

    socket!.onConnect((_) {
      debugPrint('Signaling connected: $signalingUrl');
      _isConnected = true;
      socket!.emit('register-user', <String, dynamic>{'uid': uid});
      notifyListeners();
    });

    socket!.on('incoming-call', (dynamic data) {
      final map = _socketPayloadAsMap(data);
      if (map == null) {
        debugPrint('Signaling: incoming-call ignored (bad payload type: ${data.runtimeType})');
        return;
      }
      debugPrint('Signaling: incoming-call from=${map['callerUid']} type=${map['type']}');
      onIncomingCall?.call(map);
    });

    socket!.on('call-accepted', (dynamic data) {
      final map = _socketPayloadAsMap(data);
      if (map != null) onCallAccepted?.call(map);
    });

    socket!.on('call-rejected', (dynamic data) {
      final map = _socketPayloadAsMap(data);
      if (map != null) onCallRejected?.call(map);
    });

    socket!.on('call-failed', (dynamic data) {
      final map = _socketPayloadAsMap(data);
      if (map != null) onCallFailed?.call(map);
    });

    socket!.on('offer', (dynamic data) {
      final map = _socketPayloadAsMap(data);
      if (map != null) onOffer?.call(map);
    });

    socket!.on('answer', (dynamic data) {
      final map = _socketPayloadAsMap(data);
      if (map != null) onAnswer?.call(map);
    });

    socket!.on('ice-candidate', (dynamic data) {
      final map = _socketPayloadAsMap(data);
      if (map != null) onRemoteIceCandidate?.call(map);
    });

    socket!.onDisconnect((_) {
      debugPrint('Signaling disconnected');
      _isConnected = false;
      notifyListeners();
    });

    socket!.on('connect_error', (dynamic data) {
      debugPrint('Signaling connect error: $data');
    });
    socket!.on('connect_timeout', (dynamic data) {
      debugPrint('Signaling connect timeout: $data');
    });
    socket!.on('reconnect_attempt', (dynamic attempt) {
      debugPrint('Signaling reconnect attempt: $attempt');
    });
    socket!.on('reconnect_error', (dynamic data) {
      debugPrint('Signaling reconnect error: $data');
    });
    socket!.on('reconnect_failed', (dynamic data) {
      debugPrint('Signaling reconnect failed: $data');
    });
  }

  void disconnect() {
    socket?.dispose();
    socket = null;
    _isConnected = false;
    notifyListeners();
  }

  void callUser(String targetUid, String type) {
    socket?.emit('call-user', <String, dynamic>{
      'targetUid': targetUid,
      'callerUid': currentUid,
      'type': type,
    });
  }

  /// [targetUid] is the caller to notify (the callee emits this so the server can find the caller socket).
  void acceptCall(String targetUid) {
    socket?.emit('accept-call', <String, dynamic>{'targetUid': targetUid});
  }

  void rejectCall(String targetUid) {
    socket?.emit('reject-call', <String, dynamic>{'targetUid': targetUid});
  }

  void sendOffer({required String toUid, required String sdp}) {
    socket?.emit('offer', <String, dynamic>{'to': toUid, 'sdp': sdp});
  }

  void sendAnswer({required String toUid, required String sdp}) {
    socket?.emit('answer', <String, dynamic>{'to': toUid, 'sdp': sdp});
  }

  void sendIceCandidate({
    required String toUid,
    required RTCIceCandidate candidate,
  }) {
    final c = candidate.candidate;
    if (c == null || c.isEmpty) return;
    socket?.emit('ice-candidate', <String, dynamic>{
      'to': toUid,
      'candidate': c,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }
}
