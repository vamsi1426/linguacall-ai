import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:linguacall/services/ai_translation_service.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/services/signaling_service.dart';
import 'package:linguacall/services/webrtc_service.dart';

/// Wires Socket.io signaling + WebRTC + FastAPI translation for two-phone calls.
class RealtimeCallCoordinator extends ChangeNotifier {
  RealtimeCallCoordinator({
    required this.signaling,
    required this.translation,
    required this.callState,
  });

  final SignalingService signaling;
  final AITranslationService translation;
  final CallStateService callState;

  WebRtcService? _webrtc;

  bool _armed = false;
  bool _isCaller = false;
  String? _remoteUid;

  String _sourceLang = 'te';
  String _targetLang = 'en';

  bool _translationRunning = false;

  bool get isArmed => _armed;

  void armOutgoingSession(String remoteUid) {
    _resetSessionState();
    _armed = true;
    _isCaller = true;
    _remoteUid = remoteUid;

    signaling.onCallAccepted = _onCallAccepted;
    signaling.onAnswer = _onAnswer;
    signaling.onOffer = null;
    signaling.onRemoteIceCandidate = _onRemoteIce;
  }

  Future<void> prepareCalleeSession(String callerUid) async {
    _resetSessionState();
    _armed = true;
    _isCaller = false;
    _remoteUid = callerUid;

    signaling.onOffer = _onOffer;
    signaling.onAnswer = null;
    signaling.onCallAccepted = null;
    signaling.onRemoteIceCandidate = _onRemoteIce;

    _webrtc = WebRtcService()
      ..onIceCandidate = (RTCIceCandidate c) {
        signaling.sendIceCandidate(toUid: callerUid, candidate: c);
      }
      ..onConnectionState = _onPcState
      ..onDataChannelState = _onDcState
      ..onRemotePcm = _onRemotePcm;

    await _webrtc!.initPeerConnection();
    await _webrtc!.getUserMediaAudioOnly();
  }

  Future<void> _onCallAccepted(Map<String, dynamic> data) async {
    if (!_armed || !_isCaller) return;
    final accepter = data['accepterUid'] as String?;
    if (accepter == null || accepter != _remoteUid) return;

    callState.markConnecting();

    _webrtc = WebRtcService()
      ..onIceCandidate = (RTCIceCandidate c) {
        final peer = _remoteUid;
        if (peer != null) {
          signaling.sendIceCandidate(toUid: peer, candidate: c);
        }
      }
      ..onConnectionState = _onPcState
      ..onDataChannelState = _onDcState
      ..onRemotePcm = _onRemotePcm;

    await _webrtc!.initPeerConnection();
    await _webrtc!.createDataChannelAsCaller();
    await _webrtc!.getUserMediaAudioOnly();

    final offer = await _webrtc!.createOfferAndSetLocal();
    final peer = _remoteUid;
    final sdp = offer.sdp;
    if (peer != null && sdp != null) {
      signaling.sendOffer(toUid: peer, sdp: sdp);
    }
  }

  Future<void> _onOffer(Map<String, dynamic> data) async {
    if (!_armed || _isCaller) return;
    final from = data['from'] as String?;
    final sdp = data['sdp'] as String?;
    if (from == null || sdp == null || from != _remoteUid) return;
    if (_webrtc == null) return;

    await _webrtc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final answer = await _webrtc!.createAnswerAndSetLocal();
    final out = answer.sdp;
    if (out != null) {
      signaling.sendAnswer(toUid: from, sdp: out);
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    if (!_armed || !_isCaller) return;
    final from = data['from'] as String?;
    final sdp = data['sdp'] as String?;
    if (from == null || sdp == null || from != _remoteUid) return;
    await _webrtc?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  Future<void> _onRemoteIce(Map<String, dynamic> data) async {
    if (!_armed) return;
    final from = data['from'] as String?;
    if (from == null || from != _remoteUid) return;
    final cand = data['candidate'] as String?;
    if (cand == null || cand.isEmpty) return;

    final ice = RTCIceCandidate(
      cand,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );
    await _webrtc?.addIceCandidate(ice);
  }

  void _onPcState(RTCPeerConnectionState state) {
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      unawaited(callState.endCall(reason: 'webrtc_failed'));
      endRealtimeSession();
    }
  }

  Future<void> _onDcState(RTCDataChannelState state) async {
    if (state == RTCDataChannelState.RTCDataChannelOpen) {
      await callState.markConnectedFromRealtime();
      await _startTranslation();
    }
  }

  void _onRemotePcm(Uint8List pcm) {
    translation.feedRemoteTranslatedPcm(pcm);
  }

  Future<void> _startTranslation() async {
    if (_translationRunning) return;
    _translationRunning = true;

    debugPrint('Realtime: starting translation');
    const retryDelay = Duration(seconds: 3);
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await translation.prepareRemotePlaybackPipeline();
        await translation.startTranslationStream(
          sourceLang: _sourceLang,
          targetLang: _targetLang,
          playLocally: false,
          webRtcMicActive: true,
          onTranslatedPcm: (pcm, sampleRate) {
            _webrtc?.sendPcmBytes(pcm);
          },
        );
        debugPrint('Realtime: translation started successfully');
        return;
      } catch (e, st) {
        debugPrint('Realtime: translation failed (attempt $attempt/2): $e\n$st');
        translation.notifyListeners();
        if (attempt < 2) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
    _translationRunning = false;
    if (translation.lastError == null || translation.lastError!.isEmpty) {
      translation.setDiagnosticError(
        'Translation failed to start after retries. Check network and linguacall-api logs.',
      );
    }
    debugPrint('Realtime: translation failed after retries');
  }

  /// Updates STT/TTS direction for this device (Telugu→English vs English→Telugu).
  Future<void> setCallLanguages(String sourceLang, String targetLang) async {
    _sourceLang = sourceLang;
    _targetLang = targetLang;
    if (!_translationRunning || !_armed) return;
    try {
      await translation.startTranslationStream(
        sourceLang: sourceLang,
        targetLang: targetLang,
        playLocally: false,
        webRtcMicActive: true,
        onTranslatedPcm: (pcm, sampleRate) {
          _webrtc?.sendPcmBytes(pcm);
        },
      );
    } catch (e, st) {
      debugPrint('RealtimeCallCoordinator: language update failed: $e\n$st');
    }
  }

  Future<void> pauseTranslation() async {
    _translationRunning = false;
    await translation.stopTranslationStream();
  }

  Future<void> resumeTranslation(String sourceLang, String targetLang) async {
    _sourceLang = sourceLang;
    _targetLang = targetLang;
    debugPrint('Realtime: starting translation (resume)');
    _translationRunning = true;
    try {
      await translation.prepareRemotePlaybackPipeline();
      await translation.startTranslationStream(
        sourceLang: sourceLang,
        targetLang: targetLang,
        playLocally: false,
        webRtcMicActive: true,
        onTranslatedPcm: (pcm, sampleRate) {
          _webrtc?.sendPcmBytes(pcm);
        },
      );
      debugPrint('Realtime: translation started successfully (resume)');
    } catch (e, st) {
      _translationRunning = false;
      debugPrint('Realtime: translation failed (resume): $e\n$st');
      if (translation.lastError == null || translation.lastError!.isEmpty) {
        translation.setDiagnosticError('Translation failed to start: $e');
      }
    }
  }

  Future<void> endRealtimeSession() async {
    if (!_armed && _webrtc == null) return;

    _armed = false;
    _isCaller = false;
    _remoteUid = null;
    _translationRunning = false;

    signaling.onCallAccepted = null;
    signaling.onAnswer = null;
    signaling.onOffer = null;
    signaling.onRemoteIceCandidate = null;

    await translation.stopTranslationStream();
    await _webrtc?.dispose();
    _webrtc = null;

    notifyListeners();
  }

  void _resetSessionState() {
    _translationRunning = false;
  }
}
