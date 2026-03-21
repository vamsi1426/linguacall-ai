import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:linguacall/config/app_config.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

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

  void connectAndRegister(String uid) {
    currentUid = uid;

    socket?.dispose();
    socket = IO.io(signalingUrl, <String, dynamic>{
      'transports': <String>['websocket'],
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
      if (data is Map && onIncomingCall != null) {
        onIncomingCall!(Map<String, dynamic>.from(data));
      }
    });

    socket!.on('call-accepted', (dynamic data) {
      if (data is Map && onCallAccepted != null) {
        onCallAccepted!(Map<String, dynamic>.from(data));
      }
    });

    socket!.on('call-rejected', (dynamic data) {
      if (data is Map && onCallRejected != null) {
        onCallRejected!(Map<String, dynamic>.from(data));
      }
    });

    socket!.on('call-failed', (dynamic data) {
      if (data is Map && onCallFailed != null) {
        onCallFailed!(Map<String, dynamic>.from(data));
      }
    });

    socket!.on('offer', (dynamic data) {
      if (data is Map && onOffer != null) {
        onOffer!(Map<String, dynamic>.from(data));
      }
    });

    socket!.on('answer', (dynamic data) {
      if (data is Map && onAnswer != null) {
        onAnswer!(Map<String, dynamic>.from(data));
      }
    });

    socket!.on('ice-candidate', (dynamic data) {
      if (data is Map && onRemoteIceCandidate != null) {
        onRemoteIceCandidate!(Map<String, dynamic>.from(data));
      }
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
