import 'dart:async';

import 'package:flutter/material.dart';
import 'package:linguacall/config/app_config.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/services/realtime_call_coordinator.dart';
import 'package:linguacall/services/signaling_service.dart';
import 'package:linguacall/utils/phone_uid_resolver.dart';
import 'package:provider/provider.dart';

import 'package:linguacall/utils/theme.dart';
import 'package:linguacall/screens/main_screen.dart';
import 'package:linguacall/screens/call/video_call_screen.dart';
import 'package:linguacall/screens/call/voice_call_screen.dart';

class OutgoingCallScreen extends StatefulWidget {
  final String targetPhone;
  final CallType callType;

  const OutgoingCallScreen({
    super.key,
    required this.targetPhone,
    required this.callType,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final signalingOk = await _signaling.waitForConnection();
      if (!mounted) return;

      final peerUid = await findUidByPhone(widget.targetPhone);
      final realtime = AppConfig.realtimeCallingEnabled &&
          widget.callType == CallType.voice &&
          peerUid != null &&
          signalingOk &&
          _signaling.isConnected;

      if (!signalingOk && peerUid != null && AppConfig.realtimeCallingEnabled) {
        debugPrint(
          'OutgoingCall: signaling not connected in time; using simulated call. '
          'Check network and ${AppConfig.signalingHttpUrl}',
        );
      }
      if (peerUid == null && AppConfig.realtimeCallingEnabled) {
        debugPrint(
          'OutgoingCall: no Firestore user for phone "${widget.targetPhone}" '
          '(try full E.164 as stored in users.phone). Using simulated call.',
        );
      }

      if (realtime) {
        _signaling.onCallFailed = (Map<String, dynamic> data) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Call failed: ${data['reason'] ?? 'unknown'}'),
              backgroundColor: Colors.red.shade900,
            ),
          );
          callState.endCall(reason: 'offline');
        };

        await callState.startOutgoingCall(
          targetPhone: widget.targetPhone,
          callType: widget.callType,
          simulateConnection: false,
          peerUid: peerUid,
        );
        _coordinator.armOutgoingSession(peerUid);
        _signaling.callUser(peerUid, widget.callType.name);
      } else {
        await callState.startOutgoingCall(
          targetPhone: widget.targetPhone,
          callType: widget.callType,
          simulateConnection: true,
        );
      }
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
    if (cs.peerUid != null &&
        (cs.phase == CallPhase.calling || cs.phase == CallPhase.connecting)) {
      unawaited(_coordinator.endRealtimeSession());
      unawaited(cs.endCall(reason: 'cancelled'));
    }
    _signaling.onCallFailed = null;
    _callState.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.targetPhone;
    return Consumer<CallStateService>(
      builder: (context, callState, _) {
        final isCalling = callState.phase == CallPhase.calling;
        final isConnecting = callState.phase == CallPhase.connecting;
        final isConnected = callState.phase == CallPhase.connected;
        final isEnded = callState.phase == CallPhase.ended;
        final label = isEnded
            ? 'Call ended'
            : isConnected
                ? 'Connected'
                : isConnecting
                    ? 'Connecting…'
                    : isCalling
                        ? 'Calling...'
                        : callState.phase.name;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Outgoing Call'),
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
                          const Icon(Icons.phone_in_talk, size: 70, color: AppTheme.secondaryColor),
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
                            label,
                            style: TextStyle(
                              color: isConnected ? AppTheme.secondaryColor : AppTheme.textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    InkWell(
                      onTap: () => callState.endCall(reason: 'ended'),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withOpacity(0.5),
                              blurRadius: 18,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 38),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      callState.peerUid != null
                          ? 'Realtime call: signaling + WebRTC + translated audio'
                          : 'Simulated call lifecycle: calling → connected → ended',
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

