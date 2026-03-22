import 'dart:async';

import 'package:flutter/material.dart';
import 'package:linguacall/config/app_config.dart';
import 'package:linguacall/screens/main_screen.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/services/ai_translation_service.dart';
import 'package:linguacall/services/realtime_call_coordinator.dart';
import 'package:provider/provider.dart';

import 'package:linguacall/utils/theme.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  late final VoidCallback _listener;

  late final AITranslationService _translation;
  late final CallStateService _callState;
  late final RealtimeCallCoordinator _coordinator;

  bool _translationEnabled = false;
  TranslationDirection _direction = TranslationDirection.teToEn;

  bool _useRealtime(CallStateService callState) =>
      callState.peerUid != null && AppConfig.realtimeCallingEnabled;

  Future<void> _syncTranslation() async {
    if (!mounted) return;

    final translation = _translation;
    final callState = _callState;
    final realtime = _useRealtime(callState);

    if (callState.phase == CallPhase.ended) {
      if (realtime) {
        await _coordinator.pauseTranslation();
      } else {
        await translation.stopTranslationStream();
      }
      return;
    }

    if (!realtime) {
      if (!_translationEnabled) {
        await translation.stopTranslationStream();
        return;
      }
      try {
        await translation.startTranslationStream(
          sourceLang: _sourceLang,
          targetLang: _targetLang,
        );
      } catch (e) {
        if (!mounted) return;
        debugPrint('Translation disabled: $e');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _translationEnabled = false);
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                'Cannot reach translation backend.\n'
                'Run FastAPI (uvicorn), set URLs via --dart-define=LINGUA_TRANSLATE_WS=...\n'
                'or AppConfig. Same Wi‑Fi / adb reverse as before.\n$e',
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: Colors.red.shade900,
              duration: const Duration(seconds: 8),
            ),
          );
        });
      }
      return;
    }

    // Realtime two-phone path: coordinator owns mic→WS→PCM→WebRTC.
    if (!_translationEnabled) {
      await _coordinator.pauseTranslation();
      return;
    }
    await _coordinator.resumeTranslation(_sourceLang, _targetLang);
  }

  String get _sourceLang => _direction == TranslationDirection.teToEn ? 'te' : 'en';
  String get _targetLang => _direction == TranslationDirection.teToEn ? 'en' : 'te';

  @override
  void initState() {
    super.initState();

    _translation = context.read<AITranslationService>();
    _callState = context.read<CallStateService>();
    _coordinator = context.read<RealtimeCallCoordinator>();
    final callState = _callState;
    _listener = () {
      if (!mounted) return;

      if (callState.phase == CallPhase.ended) {
        if (_useRealtime(callState)) {
          unawaited(_coordinator.endRealtimeSession());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 0)),
            (route) => false,
          );
        });
      }
    };
    callState.addListener(_listener);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_useRealtime(callState)) {
        setState(() => _translationEnabled = true);
      }
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _elapsed + const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_useRealtime(_callState)) {
      unawaited(_coordinator.endRealtimeSession());
    } else {
      unawaited(_translation.stopTranslationStream(notify: false));
    }
    _callState.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallStateService>(
      builder: (context, callState, _) {
        final target = callState.targetPhone ?? 'Unknown';
        final realtime = _useRealtime(callState);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Voice Call'),
            actions: [
              Consumer<AITranslationService>(
                builder: (context, translation, _) {
                  return IconButton(
                    tooltip: _translationEnabled ? 'Translation ON' : 'Translation OFF',
                    icon: Icon(
                      Icons.translate,
                      color: _translationEnabled ? AppTheme.secondaryColor : AppTheme.textMuted,
                    ),
                    onPressed: () async {
                      setState(() => _translationEnabled = !_translationEnabled);
                      await _syncTranslation();
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.call_end),
                onPressed: () => callState.endCall(reason: 'ended'),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: AppTheme.glassCard,
                      child: Column(
                        children: [
                          const Icon(Icons.mic, size: 70, color: AppTheme.secondaryColor),
                          const SizedBox(height: 16),
                          Text(
                            target,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Duration: ${_elapsed.inMinutes.remainder(60).toString().padLeft(2, '0')}:${_elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            callState.phase == CallPhase.connected
                                ? (realtime && callState.webrtcMediaReady ? 'Connected • live' : 'Connected')
                                : callState.phase.name,
                            style: TextStyle(
                              color: callState.phase == CallPhase.connected
                                  ? AppTheme.secondaryColor
                                  : AppTheme.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (realtime) ...[
                            const SizedBox(height: 6),
                            Text(
                              '$_sourceLang → $_targetLang (your mic to peer)',
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Translation',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                              Switch(
                                value: _translationEnabled,
                                onChanged: (v) async {
                                  setState(() => _translationEnabled = v);
                                  await _syncTranslation();
                                },
                                activeThumbColor: AppTheme.secondaryColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Telugu -> English'),
                                selected: _direction == TranslationDirection.teToEn,
                                onSelected: (selected) {
                                  setState(() => _direction = TranslationDirection.teToEn);
                                  if (_translationEnabled) unawaited(_syncTranslation());
                                },
                              ),
                              ChoiceChip(
                                label: const Text('English -> Telugu'),
                                selected: _direction == TranslationDirection.enToTe,
                                onSelected: (selected) {
                                  setState(() => _direction = TranslationDirection.enToTe);
                                  if (_translationEnabled) unawaited(_syncTranslation());
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Consumer<AITranslationService>(
                            builder: (context, translation, _) {
                              final err = translation.lastError;
                              final hasErr = err != null && err.isNotEmpty;
                              final errLine =
                                  hasErr ? (err.length > 120 ? '${err.substring(0, 117)}...' : err) : null;

                              String line;
                              if (hasErr && errLine != null) {
                                line = errLine;
                              } else if (realtime) {
                                if (!_translationEnabled) {
                                  line = 'Translation OFF — turn the switch on to translate';
                                } else if (translation.isStreaming) {
                                  if (translation.showNoSpeechHint) {
                                    line =
                                        'No speech detected — speak louder or check mic (see logcat rms)';
                                  } else {
                                    line = 'Translating… (remote peer hears translated audio)';
                                  }
                                } else if (translation.isTranslationConnecting) {
                                  line =
                                      'Connecting to translation server… (first connect can take 30–60s after cold start)';
                                } else {
                                  line = 'Translation idle — check toggle or error above';
                                }
                              } else if (translation.isStreaming) {
                                line = translation.showNoSpeechHint
                                    ? 'No speech detected — speak louder or check mic'
                                    : 'Translating… (listen on this phone’s speaker)';
                              } else {
                                line = 'Idle — enable translation & speak after backend connects';
                              }

                              return Text(
                                line,
                                style: TextStyle(
                                  color: hasErr
                                      ? Colors.orangeAccent
                                      : translation.isStreaming &&
                                              translation.showNoSpeechHint
                                          ? Colors.amberAccent
                                          : translation.isStreaming
                                              ? AppTheme.secondaryColor
                                              : AppTheme.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    InkWell(
                      onTap: () => callState.endCall(reason: 'ended'),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withOpacity(0.35),
                              blurRadius: 18,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      realtime
                          ? 'Realtime: translated audio is sent to the other phone over WebRTC. '
                              'Ensure FastAPI (${AppConfig.translationStreamUrls.first}) and signaling '
                              '(${AppConfig.signalingHttpUrl}) are reachable on your network.'
                          : 'Demo: there is no real call audio to the other number. '
                              'Your mic is sent to the AI on your PC; translated speech plays on this phone only '
                              'when the backend is reachable.',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum TranslationDirection { teToEn, enToTe }
