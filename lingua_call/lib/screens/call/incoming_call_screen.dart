import 'dart:async';

import 'package:flutter/material.dart';
import 'package:linguacall/config/app_config.dart';
import 'package:linguacall/screens/call/video_call_screen.dart';
import 'package:linguacall/screens/call/voice_call_screen.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/services/realtime_call_coordinator.dart';
import 'package:linguacall/services/signaling_service.dart';
import 'package:linguacall/screens/main_screen.dart';
import 'package:provider/provider.dart';

import 'package:linguacall/utils/theme.dart';

class IncomingCallScreen extends StatefulWidget {
  final String fromPhone;
  final CallType callType;

  /// Caller Firebase uid when delivered via Socket.io (realtime path).
  final String? callerUid;

  const IncomingCallScreen({
    super.key,
    required this.fromPhone,
    required this.callType,
    this.callerUid,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _didNavigateToConnectedScreen = false;
  late final VoidCallback _listener;
  late final CallStateService _callState;
  late final SignalingService _signaling;
  late final RealtimeCallCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _callState = context.read<CallStateService>();
    _signaling = context.read<SignalingService>();
    _coordinator = context.read<RealtimeCallCoordinator>();
    final callState = _callState;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callState.startIncomingCall(
        fromPhone: widget.fromPhone,
        callType: widget.callType,
        peerUid: widget.callerUid,
      );
    });

    _listener = () {
      final phase = callState.phase;

      if (!_didNavigateToConnectedScreen && phase == CallPhase.connected) {
        _didNavigateToConnectedScreen = true;
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => widget.callType == CallType.video
                  ? const VideoCallScreen()
                  : const VoiceCallScreen(),
            ),
          );
        });
      }

      if (phase == CallPhase.ended) {
        if (!mounted) return;
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
  }

  @override
  void dispose() {
    final cs = _callState;
    if (widget.callerUid != null &&
        AppConfig.realtimeCallingEnabled &&
        widget.callType == CallType.voice &&
        (cs.phase == CallPhase.ringing || cs.phase == CallPhase.connecting)) {
      _signaling.rejectCall(widget.callerUid!);
      unawaited(cs.endCall(reason: 'missed'));
      unawaited(_coordinator.endRealtimeSession());
    }
    _callState.removeListener(_listener);
    super.dispose();
  }

  Future<void> _accept() async {
    final callState = _callState;
    final realtime = widget.callerUid != null &&
        AppConfig.realtimeCallingEnabled &&
        widget.callType == CallType.voice;

    if (realtime) {
      try {
        final coordinator = context.read<RealtimeCallCoordinator>();
        final signaling = context.read<SignalingService>();
        await coordinator.prepareCalleeSession(widget.callerUid!);
        signaling.acceptCall(widget.callerUid!);
        await callState.acceptIncomingCall(realtime: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start WebRTC / mic: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } else {
      await callState.acceptIncomingCall();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallStateService>(
      builder: (context, callState, _) {
        final label = callState.phase == CallPhase.ringing
            ? 'Ringing...'
            : callState.phase == CallPhase.connecting
                ? 'Connecting…'
                : callState.phase.name;
        return Scaffold(
          appBar: AppBar(title: const Text('Incoming Call')),
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
                          const Icon(Icons.notifications_active, size: 70, color: AppTheme.secondaryColor),
                          const SizedBox(height: 16),
                          Text(
                            widget.fromPhone,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Accept
                        InkWell(
                          onTap: () => unawaited(_accept()),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withOpacity(0.95),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.secondaryColor.withOpacity(0.35),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: const Icon(Icons.call, color: Colors.white, size: 34),
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Reject
                        InkWell(
                          onTap: () {
                            if (widget.callerUid != null &&
                                AppConfig.realtimeCallingEnabled &&
                                widget.callType == CallType.voice) {
                              _signaling.rejectCall(widget.callerUid!);
                            }
                            callState.rejectIncomingCall();
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withOpacity(0.35),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: const Icon(Icons.call_end, color: Colors.white, size: 34),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.callerUid != null
                          ? 'Realtime incoming call (WebRTC + translation)'
                          : 'Simulated call lifecycle: ringing → connected → ended',
                      style: const TextStyle(color: AppTheme.textMuted),
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

