import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// DC binary frame: [uint32 LE sampleRate][PCM16 mono bytes]
const int _kDcPcmHeaderBytes = 4;

/// WebRTC peer connection for LinguaCall voice sessions.
///
/// Audio to the remote peer is carried **translated PCM16** over a
/// [RTCDataChannel] (label `translate-audio`).
///
/// We **do not** call [getUserMedia] for the microphone here: live speech is
/// captured by `MicStream` in the translation service and sent to the backend.
/// Opening a second mic via WebRTC caused Android conflicts (no PCM).
/// Signaling uses SCTP + data channel only (no recv-only audio transceiver) so
/// we don’t add extra m-lines that can break some Android stacks.
class WebRtcService {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;

  RTCPeerConnection? get peerConnection => _pc;
  RTCDataChannel? get dataChannel => _dataChannel;

  void Function(RTCIceCandidate candidate)? onIceCandidate;
  void Function(RTCPeerConnectionState state)? onConnectionState;
  void Function(RTCDataChannelState state)? onDataChannelState;
  /// PCM16 mono from peer; [sampleRate] Hz (from sender WAV decode).
  void Function(Uint8List pcm, int sampleRate)? onRemotePcm;

  static const String dataChannelLabel = 'translate-audio';

  /// SCTP often caps a single binary message (~64KB). Split larger PCM.
  static const int _maxDcBinaryBytes = 16384;

  /// Max PCM bytes per SCTP message after header.
  int get _maxPcmPayloadPerMessage => _maxDcBinaryBytes - _kDcPcmHeaderBytes;

  /// While DTLS/SCTP connects, translated PCM may arrive before [RTCDataChannelOpen].
  final List<_PendingOutPcm> _pendingPcmOut = <_PendingOutPcm>[];
  static const int _maxPendingPcmChunks = 48;
  int _skippedSendLogCount = 0;

  Future<RTCPeerConnection> initPeerConnection() async {
    final configuration = <String, dynamic>{
      'sdpSemantics': 'unified-plan',
      'iceServers': <Map<String, dynamic>>[
        {'urls': 'stun:stun.l.google.com:19302'},
        // Public TURN — mobile ↔ mobile often needs relay when STUN-only P2P fails.
        {
          'urls': <String>[
            'turn:openrelay.metered.ca:80',
            'turn:openrelay.metered.ca:443',
            'turn:openrelay.metered.ca:443?transport=tcp',
          ],
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
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
      debugPrint('WebRtcService: peerConnectionState=$state');
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

    // Reliable, ordered delivery for translated PCM (unordered + lossy was dropping audio).
    final init = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = -1;

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

  /// Sends PCM16 mono with a leading sample-rate tag so the peer can configure playback.
  Future<void> sendPcmBytes(Uint8List pcm, {int sampleRate = 16000}) async {
    final dc = _dataChannel;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      if (_pendingPcmOut.length < _maxPendingPcmChunks) {
        _pendingPcmOut.add(_PendingOutPcm(Uint8List.fromList(pcm), sampleRate));
      }
      if (_skippedSendLogCount < 8 || _skippedSendLogCount % 30 == 0) {
        debugPrint(
          'WebRtcService: PCM held until data channel open '
          '(dc=${dc == null ? "null" : dc.state} pendingChunks=${_pendingPcmOut.length} '
          'pcmBytes=${pcm.length} sr=$sampleRate)',
        );
      }
      _skippedSendLogCount++;
      return;
    }
    await _sendPcmInternal(pcm, sampleRate);
  }

  Future<void> _sendPcmInternal(Uint8List pcm, int sampleRate) async {
    final dc = _dataChannel;
    if (dc == null) return;
    try {
      final pcmMax = _maxPcmPayloadPerMessage;
      var offset = 0;
      while (offset < pcm.length) {
        final end = offset + pcmMax < pcm.length ? offset + pcmMax : pcm.length;
        final sliceLen = end - offset;
        final packet = Uint8List(_kDcPcmHeaderBytes + sliceLen);
        final bd = ByteData.sublistView(packet);
        bd.setUint32(0, sampleRate, Endian.little);
        packet.setRange(_kDcPcmHeaderBytes, _kDcPcmHeaderBytes + sliceLen, pcm, offset);
        await dc.send(RTCDataChannelMessage.fromBinary(packet));
        offset = end;
      }
    } catch (e, st) {
      debugPrint('WebRtcService: send pcm failed: $e\n$st');
    }
  }

  Future<void> _flushPendingPcmOut() async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) return;
    if (_pendingPcmOut.isEmpty) return;
    debugPrint('WebRtcService: flushing ${_pendingPcmOut.length} pending PCM chunk(s)');
    while (_pendingPcmOut.isNotEmpty) {
      final p = _pendingPcmOut.removeAt(0);
      await _sendPcmInternal(p.pcm, p.sampleRate);
    }
  }

  void _wireDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('WebRtcService: dataChannel state=$state label=${channel.label}');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        unawaited(_flushPendingPcmOut());
      }
      onDataChannelState?.call(state);
    };

    var rxLog = 0;
    channel.onMessage = (RTCDataChannelMessage message) {
      if (!message.isBinary) return;
      final bytes = message.binary;
      final parsed = _parseDcPcmMessage(bytes);
      if (rxLog < 12 || rxLog % 50 == 0) {
        debugPrint(
          'WebRtcService: received PCM from peer (${bytes.length} b, sr=${parsed.rate}, '
          'pcm=${parsed.pcm.length} b, framed=${parsed.framed})',
        );
      }
      rxLog++;
      onRemotePcm?.call(parsed.pcm, parsed.rate);
    };
  }

  Future<void> dispose() async {
    _pendingPcmOut.clear();
    _skippedSendLogCount = 0;
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

class _PendingOutPcm {
  _PendingOutPcm(this.pcm, this.sampleRate);
  final Uint8List pcm;
  final int sampleRate;
}

class _ParsedDcPcm {
  _ParsedDcPcm({required this.pcm, required this.rate, required this.framed});
  final Uint8List pcm;
  final int rate;
  final bool framed;
}

/// Framed: 4 bytes uint32-LE sample rate + PCM16 (even length). Legacy: raw PCM @ 16 kHz.
_ParsedDcPcm _parseDcPcmMessage(Uint8List bytes) {
  if (bytes.length >= _kDcPcmHeaderBytes + 2) {
    final bd = ByteData.sublistView(bytes);
    final sr = bd.getUint32(0, Endian.little);
    final pcmLen = bytes.length - _kDcPcmHeaderBytes;
    if (sr >= 6000 &&
        sr <= 96000 &&
        pcmLen >= 2 &&
        pcmLen.isEven &&
        _looksPlausibleRate(sr)) {
      return _ParsedDcPcm(
        pcm: bytes.sublist(_kDcPcmHeaderBytes),
        rate: sr,
        framed: true,
      );
    }
  }
  return _ParsedDcPcm(pcm: bytes, rate: 16000, framed: false);
}

bool _looksPlausibleRate(int sr) {
  // Common rates; avoids mis-parsing random PCM as header.
  const common = <int>{
    8000,
    11025,
    12000,
    16000,
    22050,
    24000,
    32000,
    44100,
    48000,
  };
  return common.contains(sr);
}
