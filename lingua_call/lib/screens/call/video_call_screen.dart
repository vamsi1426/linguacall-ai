import 'dart:async';

import 'package:flutter/material.dart';
import 'package:linguacall/screens/main_screen.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/services/ai_translation_service.dart';
import 'package:provider/provider.dart';

import 'package:linguacall/utils/theme.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  late final VoidCallback _listener;

  late final AITranslationService _translation;
  late final CallStateService _callState;

  bool _translationEnabled = false;
  TranslationDirection _direction = TranslationDirection.teToEn;

  String get _sourceLang => _direction == TranslationDirection.teToEn ? 'te' : 'en';
  String get _targetLang => _direction == TranslationDirection.teToEn ? 'en' : 'te';

  Future<void> _syncTranslation() async {
    if (!mounted) return;

    final translation = _translation;
    final callState = _callState;

    if (!_translationEnabled || callState.phase == CallPhase.ended) {
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Cannot reach translation PC. Check FastAPI on PC, firewall, and IP in ai_translation_service.dart.\n$e',
              style: const TextStyle(fontSize: 13),
            ),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 8),
          ),
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _translation = context.read<AITranslationService>();
    _callState = context.read<CallStateService>();
    final callState = _callState;
    _listener = () {
      if (!mounted) return;

      if (callState.phase == CallPhase.ended && mounted) {
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

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _elapsed + const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_translation.stopTranslationStream());
    _callState.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallStateService>(
      builder: (context, callState, _) {
        final target = callState.targetPhone ?? 'Unknown';
        return Scaffold(
          appBar: AppBar(
            title: const Text('Video Call'),
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
                          Container(
                            width: double.infinity,
                            height: 220,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0038F5), Color(0xFF9F03FF)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.videocam, size: 80, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            target,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
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
                                ? 'Connected'
                                : callState.phase.name,
                            style: TextStyle(
                              color: callState.phase == CallPhase.connected ? AppTheme.secondaryColor : AppTheme.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
                              final line = err != null && err.isNotEmpty
                                  ? (err.length > 120 ? '${err.substring(0, 117)}...' : err)
                                  : translation.isStreaming
                                      ? 'Translating… (this phone speaker)'
                                      : translation.isTranslationConnecting
                                          ? 'Connecting to translation server…'
                                          : 'Idle — backend must be reachable';
                              return Text(
                                line,
                                style: TextStyle(
                                  color: err != null && err.isNotEmpty
                                      ? Colors.orangeAccent
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
                    const Text(
                      'Demo: video & remote audio are not real. Translation uses your PC backend; '
                      'TTS plays on this device when ws://<PC_IP>:8000 works.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
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

