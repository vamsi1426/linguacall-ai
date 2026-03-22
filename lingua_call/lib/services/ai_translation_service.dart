import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:convert';
// Uint8List is re-exported by flutter/foundation.dart, so we don't need dart:typed_data here.

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:linguacall/config/app_config.dart';

/// Parallel AI translation for live calls.
///
/// Assumptions (based on your `/ws/translate-stream` contract):
/// - First send a JSON "start" message with language direction and enabled flag.
/// - Then stream raw PCM16 little-endian mono at 16kHz as binary.
/// - Server sends back translated audio as WAV bytes per chunk.
/// - We decode WAV -> PCM16 and play it locally (without altering call media/WebRTC).
class AITranslationService extends ChangeNotifier {
  static const int _sampleRate = 16000;
  static const int _channelCount = 1; // mono
  static const Duration _chunkDuration = Duration(milliseconds: 500); // 0.5s
  static const int _bytesPerSample = 2; // PCM16

  WebSocket? _webSocket;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamSubscription<dynamic>? _wsSubscription;

  Timer? _pcmWatchdog;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  /// True while opening websocket / setting up mic (before [_isStreaming] is true).
  bool _translationConnecting = false;
  bool get isTranslationConnecting => _translationConnecting;

  String? _lastError;
  String? get lastError => _lastError;

  /// Set when translation fails outside [startTranslationStream] (e.g. coordinator retries exhausted).
  void setDiagnosticError(String message) {
    _lastError = message;
    notifyListeners();
  }

  String? _sourceLang;
  String? _targetLang;

  /// Last error from [_openTranslationWebSocket] when it returns null.
  Object? _lastTranslationConnectError;

  bool _playLocally = true;
  void Function(Uint8List pcm, int sampleRate)? _onTranslatedPcm;

  // Microphone PCM chunking.
  final List<int> _micBuffer = <int>[];
  int get _chunkBytes => (_sampleRate * _chunkDuration.inMilliseconds ~/ 1000) * _bytesPerSample;

  /// Connects to the first reachable translation WebSocket URL with retries per URL.
  Future<WebSocket?> _openTranslationWebSocket() async {
    _lastTranslationConnectError = null;
    Object? lastErr;
    const delayBetween = Duration(seconds: 2);
    final timeout = AppConfig.translationWsConnectTimeout;
    const maxAttempts = AppConfig.translationWsRetries;

    for (final url in AppConfig.translationStreamUrls) {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          debugPrint(
            'AITranslationService: connecting to websocket $url '
            '(attempt $attempt/$maxAttempts, timeout ${timeout.inSeconds}s)',
          );
          final ws = await WebSocket.connect(url).timeout(timeout);
          debugPrint('AITranslationService: websocket connected ($url)');
          return ws;
        } catch (e) {
          lastErr = e;
          debugPrint('AITranslationService: connect failed for $url: $e');
          if (attempt < maxAttempts) {
            await Future<void>.delayed(delayBetween);
          }
        }
      }
    }
    _lastTranslationConnectError = lastErr;
    return null;
  }

  // Playback: flutter_pcm_sound feeds from a callback. We queue PCM frames (no WAV headers).
  final Queue<Uint8List> _pcmQueue = Queue<Uint8List>();
  bool _playbackActive = false;

  /// Serializes remote DC PCM so rate switches complete before the next chunk is queued.
  Future<void>? _remotePcmSerial;
  int _playbackSampleRate = _sampleRate;
  int _receivedChunkCount = 0;
  int _fedChunkCount = 0;

  Future<void> startTranslationStream({
    required String sourceLang,
    required String targetLang,
    bool playLocally = true,
    void Function(Uint8List pcm, int sampleRate)? onTranslatedPcm,
    /// True when WebRTC already called `getUserMedia` — second mic capture may fail on some devices.
    bool webRtcMicActive = false,
  }) async {
    // Idempotency: avoid reconnect if the settings match.
    if (_isStreaming &&
        _sourceLang == sourceLang &&
        _targetLang == targetLang &&
        _playLocally == playLocally) {
      debugPrint('AITranslationService: already streaming ($sourceLang -> $targetLang)');
      return;
    }

    await stopTranslationStream();

    _translationConnecting = true;
    notifyListeners();

    try {
    _lastError = null;
    _sourceLang = sourceLang;
    _targetLang = targetLang;
    _playLocally = playLocally;
    _onTranslatedPcm = onTranslatedPcm;
    _receivedChunkCount = 0;
    _fedChunkCount = 0;
    _remotePcmDropLog = 0;

    debugPrint('AITranslationService: starting ($sourceLang -> $targetLang)');

    if (webRtcMicActive) {
      debugPrint(
        'AITranslationService: WARNING: WebRTC already holds a microphone capture; '
        'MicStream may fail or yield silence on some Android devices. If translation stays idle, check device logs.',
      );
    }

    final micOk = await _ensureMicPermission();
    if (!micOk) {
      _lastError = 'Microphone permission denied.';
      notifyListeners();
      throw StateError(_lastError ?? 'Microphone permission denied.');
    }

    // Start speaker pipeline **before** WebSocket connect so WebRTC can play peer
    // translated audio while the translation socket is still handshaking.
    await _configurePlaybackAudioSession();
    await _setupPcmPlayer(sampleRate: _playbackSampleRate);
    _playbackActive = true;
    FlutterPcmSound.start();

    // Connect and send start JSON before heavy audio setup so the server’s first
    // message is not delayed (avoids spurious “no start JSON” closes on slow devices).
    debugPrint('AITranslationService: opening translation websocket…');
    final ws = await _openTranslationWebSocket();
    if (ws == null) {
      final lastErr = _lastTranslationConnectError;
      const prodHint =
          ' Check mobile data/Wi‑Fi; first request to Render can take 30–60s after sleep.';
      const localHint = ' Run FastAPI locally or set LINGUA_TRANSLATE_WS.';
      const hint = AppConfig.profile == 'prod' ? prodHint : localHint;
      _lastError =
          'Failed to connect to translation backend after ${AppConfig.translationWsRetries} tries '
          '(${AppConfig.translationWsTimeoutSec}s each): $lastErr.$hint';
      notifyListeners();
      throw StateError(_lastError!);
    }
    _webSocket = ws;
    _wsSubscription = null;

    _wsSubscription = _webSocket!.listen(
      (data) async {
        // Server can send metadata messages as JSON strings.
        if (data is String) {
          debugPrint('AITranslationService: websocket server text: $data');
          return;
        }

        if (data is List<int>) {
          data = Uint8List.fromList(data);
        }

        if (data is! Uint8List) {
          debugPrint('AITranslationService: unexpected message type: ${data.runtimeType}');
          return;
        }

        // Expect WAV bytes for each translated chunk.
        final wavBytes = data;
        if (wavBytes.length < 12) return;

        final decoded = _decodeWavToPcm16(wavBytes);
        if (decoded == null) {
          debugPrint('AITranslationService: could not decode translated WAV chunk (${wavBytes.length} bytes)');
          return;
        }

        // If sample rate changes, reconfigure playback.
        if (decoded.sampleRate != _playbackSampleRate) {
          debugPrint(
            'AITranslationService: reconfigure playback sampleRate $_playbackSampleRate -> ${decoded.sampleRate}',
          );
          await _setupPcmPlayer(sampleRate: decoded.sampleRate);
        }

        _onTranslatedPcm?.call(decoded.pcmBytes, decoded.sampleRate);

        if (_playLocally) {
          _pcmQueue.add(decoded.pcmBytes);
        }
        _receivedChunkCount++;
        if (_receivedChunkCount <= 5 || _receivedChunkCount % 10 == 0) {
          debugPrint(
            'AITranslationService: received translated audio chunk #$_receivedChunkCount '
            '(pcmBytes=${decoded.pcmBytes.length}, sr=${decoded.sampleRate})',
          );
        }
        // Critical: flutter_pcm_sound only schedules the next feed callback after a
        // successful feed(). If the first onFeed(0) ran while the queue was still
        // empty, we must push audio as soon as it arrives.
        unawaited(_feedNextPcmChunk());
      },
      onError: (e) async {
        _lastError = 'Translation websocket error: $e';
        debugPrint('AITranslationService: websocket error: $_lastError');
        await stopTranslationStream();
      },
      onDone: () async {
        final code = _webSocket?.closeCode;
        final reason = _webSocket?.closeReason;
        debugPrint(
          'AITranslationService: websocket closed (closeCode=$code closeReason=$reason)',
        );
        if (_isStreaming) {
          _lastError = AppConfig.profile == 'prod'
              ? 'Translation disconnected (ws close $code). '
                  'Check ${AppConfig.translationStreamUrls.first} and your network.'
              : 'Translation disconnected (ws close $code). '
                  'Run uvicorn on the PC, then: adb reverse tcp:8000 tcp:8000 '
                  '(or set LINGUA_TRANSLATE_WS).';
          notifyListeners();
        }
        await stopTranslationStream();
      },
    );

    // 1) Send start JSON immediately after the socket listener is attached.
    final startPayload = <String, dynamic>{
      'type': 'start',
      'source': sourceLang,
      'target': targetLang,
      'enabled': true,
    };
    debugPrint('AITranslationService: sending start JSON: $startPayload');
    try {
      _webSocket!.add(jsonEncode(startPayload));
      debugPrint('AITranslationService: start JSON sent');
    } catch (e, st) {
      debugPrint('AITranslationService: FAILED to send start JSON: $e\n$st');
      _lastError = 'Failed to send start message to translation server: $e';
      notifyListeners();
      await stopTranslationStream();
      throw StateError(_lastError!);
    }

    // Mic capture + PCM streaming to backend.
    _micBuffer.clear();
    _pcmQueue.clear();

    // Mark streaming before mic chunks arrive.
    _isStreaming = true;
    notifyListeners();

    var pcmChunksSent = 0;
    _pcmWatchdog?.cancel();
    _pcmWatchdog = Timer(const Duration(seconds: 1), () {
      if (!_isStreaming) return;
      if (pcmChunksSent == 0) {
        debugPrint(
          'AITranslationService: WARNING: no PCM chunks sent to websocket within 1s '
          '(mic blocked, permission issue, or WebRTC mic conflict)',
        );
      }
    });

    try {
      _micSubscription = MicStream.microphone(
        audioSource: AudioSource.DEFAULT,
        sampleRate: _sampleRate,
        channelConfig: ChannelConfig.CHANNEL_IN_MONO,
        audioFormat: AudioFormat.ENCODING_PCM_16BIT,
      ).listen(
        (Uint8List chunk) {
          if (!_isStreaming) return;

          // mic_stream gives raw PCM bytes; chunk boundaries are not guaranteed.
          _micBuffer.addAll(chunk);

          // Keep chunk sizes stable: 500ms -> _chunkBytes bytes.
          while (_micBuffer.length >= _chunkBytes) {
            final out = Uint8List.fromList(_micBuffer.sublist(0, _chunkBytes));
            _micBuffer.removeRange(0, _chunkBytes);
            pcmChunksSent++;
            if (pcmChunksSent <= 3 || pcmChunksSent % 50 == 0) {
              debugPrint(
                'AITranslationService: sending PCM chunk #$pcmChunksSent (${out.length} bytes)',
              );
            }
            _webSocket?.add(out);
          }
        },
        onError: (Object e) async {
          _lastError = 'Mic stream error: $e';
          debugPrint('AITranslationService: mic stream FAILED: $_lastError');
          notifyListeners();
          await stopTranslationStream();
        },
      );
      debugPrint('AITranslationService: mic stream started (subscription active)');
    } catch (e, st) {
      debugPrint('AITranslationService: mic stream start FAILED: $e\n$st');
      _lastError = 'Could not start microphone capture: $e';
      notifyListeners();
      await stopTranslationStream();
      rethrow;
    }
    } finally {
      _translationConnecting = false;
      notifyListeners();
    }
  }

  Future<void> stopTranslationStream({bool notify = true}) async {
    if (!_isStreaming && _webSocket == null && _micSubscription == null) return;

    _pcmWatchdog?.cancel();
    _pcmWatchdog = null;

    _translationConnecting = false;
    _isStreaming = false;
    if (notify) {
      notifyListeners();
    }

    await _micSubscription?.cancel();
    _micSubscription = null;

    try {
      await _wsSubscription?.cancel();
    } catch (_) {}

    try {
      await _webSocket?.close();
    } catch (_) {}

    _wsSubscription = null;
    _webSocket = null;

    _micBuffer.clear();
    _pcmQueue.clear();

    _remotePcmSerial = null;
    _playbackActive = false;

    try {
      await FlutterPcmSound.release();
    } catch (_) {}

    _sourceLang = null;
    _targetLang = null;
    _playLocally = true;
    _onTranslatedPcm = null;
  }

  static int _remotePcmDropLog = 0;

  /// PCM16 mono from the remote peer (post-translation), played like TTS output.
  void feedRemoteTranslatedPcm(Uint8List pcmBytes, {int sampleRate = 16000}) {
    if (!_playbackActive) {
      if (_remotePcmDropLog < 6) {
        debugPrint(
          'AITranslationService: dropped remote PCM (${pcmBytes.length} b) — playback not ready yet',
        );
      }
      _remotePcmDropLog++;
      return;
    }
    _remotePcmSerial = (_remotePcmSerial ?? Future<void>.value()).then((_) async {
      await _enqueueRemotePcm(pcmBytes, sampleRate);
    }).catchError((Object e, StackTrace st) {
      debugPrint('AITranslationService: remote PCM chain error: $e\n$st');
    });
  }

  Future<void> _enqueueRemotePcm(Uint8List pcmBytes, int sampleRate) async {
    if (!_playbackActive) return;
    if (sampleRate != _playbackSampleRate) {
      debugPrint(
        'AITranslationService: remote PCM reconfigure sampleRate $_playbackSampleRate -> $sampleRate',
      );
      await _setupPcmPlayer(sampleRate: sampleRate);
    }
    if (!_playbackActive) return;
    _pcmQueue.add(pcmBytes);
    unawaited(_feedNextPcmChunk());
  }

  /// Prepares playback for a realtime call before [startTranslationStream] (optional).
  Future<void> prepareRemotePlaybackPipeline() async {
    await _configurePlaybackAudioSession();
    await _setupPcmPlayer(sampleRate: _playbackSampleRate);
  }

  Future<void> _configurePlaybackAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );
      await session.setActive(true);
      debugPrint('AITranslationService: audio session configured (media/speech)');
    } catch (e, st) {
      debugPrint('AITranslationService: audio session configure failed: $e\n$st');
    }
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      // Let the user open app settings themselves.
      await openAppSettings();
    }

    return false;
  }

  Future<void> _setupPcmPlayer({required int sampleRate}) async {
    _playbackSampleRate = sampleRate;

    // Keep it consistent with our expected backend audio.
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: _channelCount)
        .onError((Object e, StackTrace st) {
      debugPrint('AITranslationService: PCM setup error: $e');
    });

    await FlutterPcmSound.setFeedThreshold(sampleRate ~/ 10);
    FlutterPcmSound.setFeedCallback(_onPcmSoundFeed);
  }

  Future<void> _onPcmSoundFeed(int remainingFrames) async {
    await _feedNextPcmChunk();
  }

  /// Sends one queued PCM chunk to [FlutterPcmSound]. Must be called when new
  /// audio arrives if the initial feed callback ran with an empty queue.
  Future<void> _feedNextPcmChunk() async {
    if (!_playbackActive) return;
    if (_pcmQueue.isEmpty) return;

    final pcmBytes = _pcmQueue.removeFirst();
    await FlutterPcmSound
        .feed(PcmArrayInt16(bytes: ByteData.sublistView(pcmBytes)))
        .onError((Object e, StackTrace st) {
      debugPrint('AITranslationService: feed failed: $e');
    });
    _fedChunkCount++;
    if (_fedChunkCount <= 5 || _fedChunkCount % 10 == 0) {
      debugPrint('AITranslationService: fed PCM to device (chunk $_fedChunkCount, ${pcmBytes.length} bytes)');
    }
  }

  /// Returns PCM16 (mono) + sample rate extracted from a WAV chunk.
  ///
  /// If the chunk isn't supported (non-PCM16, multi-channel without simple downmix),
  /// returns null.
  _DecodedPcm16? _decodeWavToPcm16(Uint8List wavBytes) {
    // Minimal WAV parsing: RIFF -> fmt -> data.
    // All multi-byte fields are little-endian.
    if (wavBytes.length < 44) return null;
    if (String.fromCharCodes(wavBytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(wavBytes.sublist(8, 12)) != 'WAVE') return null;

    int offset = 12;
    int sampleRate = _sampleRate;
    int numChannels = 1;
    int bitsPerSample = 16;
    bool isPcm = false;
    Uint8List? dataPcm;

    while (offset + 8 <= wavBytes.length) {
      final chunkId = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final chunkSize = _readU32LE(wavBytes, offset + 4);
      offset += 8;

      if (chunkId == 'fmt ') {
        // fmt chunk: audioFormat(2), numChannels(2), sampleRate(4), byteRate(4), blockAlign(2), bitsPerSample(2)
        if (offset + 16 <= wavBytes.length) {
          final audioFormat = _readU16LE(wavBytes, offset);
          numChannels = _readU16LE(wavBytes, offset + 2);
          sampleRate = _readU32LE(wavBytes, offset + 4);
          bitsPerSample = _readU16LE(wavBytes, offset + 14);
          isPcm = audioFormat == 1;
        }
      } else if (chunkId == 'data') {
        if (offset + chunkSize <= wavBytes.length) {
          dataPcm = Uint8List.fromList(wavBytes.sublist(offset, offset + chunkSize));
        }
        break;
      }

      offset += chunkSize;
    }

    if (!isPcm || bitsPerSample != 16 || dataPcm == null) return null;

    // Downmix to mono if needed (simple average of L/R for 16-bit PCM).
    if (numChannels == 1) {
      return _DecodedPcm16(pcmBytes: dataPcm, sampleRate: sampleRate);
    }

    if (numChannels == 2) {
      final bytes = dataPcm;
      final frameCount = bytes.length ~/ (2 * numChannels);
      final out = Uint8List(frameCount * 2);

      for (int i = 0; i < frameCount; i++) {
        final left = _readI16LE(bytes, i * 4);
        final right = _readI16LE(bytes, i * 4 + 2);
        final avg = ((left + right) / 2).round().clamp(-32768, 32767);
        out[i * 2] = avg & 0xFF;
        out[i * 2 + 1] = (avg >> 8) & 0xFF;
      }

      return _DecodedPcm16(pcmBytes: out, sampleRate: sampleRate);
    }

    // Unsupported channel count.
    return null;
  }

  int _readU32LE(Uint8List b, int offset) =>
      b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16) | (b[offset + 3] << 24);

  int _readU16LE(Uint8List b, int offset) =>
      b[offset] | (b[offset + 1] << 8);

  int _readI16LE(Uint8List b, int offset) {
    final u = _readU16LE(b, offset);
    return (u & 0x8000) != 0 ? u - 0x10000 : u;
  }
}

class _DecodedPcm16 {
  final Uint8List pcmBytes;
  final int sampleRate;

  _DecodedPcm16({required this.pcmBytes, required this.sampleRate});
}
