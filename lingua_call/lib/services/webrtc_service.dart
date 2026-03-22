import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC peer connection for LinguaCall voice sessions.
///
/// Audio to the remote peer is carried **translated PCM16** over a
/// [RTCDataChannel] (label `translate-audio`).
///
/// We **do not** call [getUserMedia] for the microphone here: live speech is
/// captured by `MicStream` in the translation service and sent to the backend.
/// Opening a second mic via WebRTC caused Android conflicts (no PCM).
/// Instead we add a **recv-only** audio transceiver so SDP has an audio m-line
/// without capturing the device mic.
class WebRtcService {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;

  RTCPeerConnection? get peerConnection => _pc;
  RTCDataChannel? get dataChannel => _dataChannel;

  void Function(RTCIceCandidate candidate)? onIceCandidate;
  void Function(RTCPeerConnectionState state)? onConnectionState;
  void Function(RTCDataChannelState state)? onDataChannelState;
  void Function(Uint8List pcm)? onRemotePcm;

  static const String dataChannelLabel = 'translate-audio';

  Future<RTCPeerConnection> initPeerConnection() async {
    final configuration = <String, dynamic>{
      'sdpSemantics': 'unified-plan',
      'iceServers': <Map<String, dynamic>>[
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    _pc = await createPeerConnection(configuration, {
      'mandatory': <String, dynamic>{},
      'optional': <dynamic>[
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      onIceCandidate?.call(candidate);
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      onConnectionState?.call(state);
    };

    _pc!.onDataChannel = (RTCDataChannel channel) {
      _wireDataChannel(channel);
    };

    return _pc!;
  }

  /// Adds an audio m-line for SDP / ICE compatibility **without** opening the mic.
  /// The callee path typically relies on the caller’s offer; this is mainly for the caller.
  Future<void> addRecvOnlyAudioForSignalingCompatibility() async {
    if (_pc == null) throw StateError('Peer connection not created');
    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.RecvOnly,
      ),
    );
  }

  /// Legacy: captures microphone via WebRTC (conflicts with [MicStream] on Android).
  /// Not used for realtime translation calls.
  Future<void> getUserMediaAudioOnly() async {
    if (_pc == null) throw StateError('Peer connection not created');

    final constraints = <String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
      },
      'video': false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    for (final t in _localStream!.getAudioTracks()) {
      t.enabled = false;
      await _pc!.addTrack(t, _localStream!);
    }
  }

  Future<void> createDataChannelAsCaller() async {
    if (_pc == null) throw StateError('Peer connection not created');

    final init = RTCDataChannelInit()
      ..ordered = false
      ..maxRetransmits = 0;

    final dc = await _pc!.createDataChannel(dataChannelLabel, init);
    _wireDataChannel(dc);
  }

  Future<RTCSessionDescription> createOfferAndSetLocal() async {
    if (_pc == null) throw StateError('Peer connection not created');

    final offer = await _pc!.createOffer(<String, dynamic>{});
    await _pc!.setLocalDescription(offer);
    return offer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _pc?.setRemoteDescription(description);
  }

  Future<RTCSessionDescription> createAnswerAndSetLocal() async {
    if (_pc == null) throw StateError('Peer connection not created');

    final answer = await _pc!.createAnswer(<String, dynamic>{});
    await _pc!.setLocalDescription(answer);
    return answer;
  }

  Future<void> addIceCandidate(RTCIceCandidate? candidate) async {
    if (candidate == null || _pc == null) return;
    await _pc!.addCandidate(candidate);
  }

  Future<void> sendPcmBytes(Uint8List pcm) async {
    final dc = _dataChannel;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      await dc.send(RTCDataChannelMessage.fromBinary(pcm));
    } catch (e, st) {
      debugPrint('WebRtcService: send pcm failed: $e\n$st');
    }
  }

  void _wireDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onDataChannelState = (RTCDataChannelState state) {
      onDataChannelState?.call(state);
    };

    channel.onMessage = (RTCDataChannelMessage message) {
      if (!message.isBinary) return;
      onRemotePcm?.call(message.binary);
    };
  }

  Future<void> dispose() async {
    try {
      await _dataChannel?.close();
    } catch (_) {}

    _dataChannel = null;

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}

    _localStream = null;

    try {
      await _pc?.close();
    } catch (_) {}

    _pc = null;
  }
}
