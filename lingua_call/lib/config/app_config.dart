import 'package:flutter/foundation.dart';

/// Central URLs for LinguaCall (dev vs prod).
///
/// Override at build time:
/// `--dart-define=LINGUA_PROFILE=prod`
/// `--dart-define=LINGUA_SIGNALING_URL=http://192.168.1.10:3000`
/// `--dart-define=LINGUA_TRANSLATE_WS=ws://192.168.1.10:8000/ws/translate-stream`
class AppConfig {
  AppConfig._();

  static const String profile =
      String.fromEnvironment('LINGUA_PROFILE', defaultValue: 'local');

  /// When false, calls use the legacy simulated timer + local-only translation demo.
  static const bool realtimeCallingEnabled = bool.fromEnvironment(
    'LINGUA_REALTIME',
    defaultValue: true,
  );

  static const String _defaultSignalingLocal = 'http://127.0.0.1:3000';
  static const String _defaultTranslateWsLocal = 'ws://127.0.0.1:8000/ws/translate-stream';

  /// Socket.io / HTTP signaling (Node server).
  static String get signalingHttpUrl {
    const override = String.fromEnvironment('LINGUA_SIGNALING_URL');
    if (override.isNotEmpty) return override;
    if (profile == 'prod') {
      const prod = String.fromEnvironment('LINGUA_SIGNALING_URL_PROD');
      if (prod.isNotEmpty) return prod;
    }
    return _defaultSignalingLocal;
  }

  /// FastAPI `/ws/translate-stream` endpoints (tried in order).
  static List<String> get translationStreamUrls {
    const single = String.fromEnvironment('LINGUA_TRANSLATE_WS');
    if (single.isNotEmpty) return <String>[single];

    if (profile == 'prod') {
      const prod = String.fromEnvironment('LINGUA_TRANSLATE_WS_PROD');
      if (prod.isNotEmpty) return <String>[prod];
    }

    // Dev: host loopback, Android emulator host alias, LAN placeholders.
    return <String>[
      _defaultTranslateWsLocal,
      'ws://10.0.2.2:8000/ws/translate-stream',
    ];
  }

  static void debugLogEndpoints() {
    debugPrint(
      'AppConfig: profile=$profile signaling=$signalingHttpUrl '
      'translate=${translationStreamUrls.join(", ")}',
    );
  }
}
