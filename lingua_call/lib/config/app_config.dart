import 'package:flutter/foundation.dart';

/// Central URLs for LinguaCall (local vs internet deployment).
///
/// **Local (default)** — `LINGUA_PROFILE` unset or `local`:
/// - Signaling: `http://127.0.0.1:3000`
/// - Translation WS: `ws://127.0.0.1:8000/ws/translate-stream` (+ Android emulator alias)
///
/// **Production / mobile data** — build with:
/// ```text
/// flutter build apk --release \
///   --dart-define=LINGUA_PROFILE=prod \
///   --dart-define=LINGUA_SIGNALING_URL=https://linguacall-signal.onrender.com \
///   --dart-define=LINGUA_TRANSLATE_WS=wss://linguacall-api.onrender.com/ws/translate-stream
/// ```
///
/// Overrides always win: if `LINGUA_SIGNALING_URL` or `LINGUA_TRANSLATE_WS` is non-empty,
/// it is used regardless of profile (handy for staging URLs without switching profile).
class AppConfig {
  AppConfig._();

  /// `local` = USB/Wi‑Fi dev defaults; `prod` = HTTPS / WSS placeholders until you pass defines.
  static const String profile =
      String.fromEnvironment('LINGUA_PROFILE', defaultValue: 'local');

  /// When false, calls use the legacy simulated timer + local-only translation demo.
  static const bool realtimeCallingEnabled = bool.fromEnvironment(
    'LINGUA_REALTIME',
    defaultValue: true,
  );

  /// Per-attempt timeout for `WebSocket.connect` to `/ws/translate-stream`.
  /// Render (and similar hosts) often need 30–60s on cold start; 6s caused frequent timeouts.
  static const int translationWsTimeoutSec = int.fromEnvironment(
    'LINGUA_TRANSLATE_WS_TIMEOUT_SEC',
    defaultValue: 45,
  );

  /// Retries per URL if connect fails (transient network / cold start).
  static const int translationWsRetries = int.fromEnvironment(
    'LINGUA_TRANSLATE_WS_RETRIES',
    defaultValue: 3,
  );

  static Duration get translationWsConnectTimeout =>
      const Duration(seconds: translationWsTimeoutSec);

  static const String _defaultSignalingLocal = 'http://127.0.0.1:3000';
  static const String _defaultTranslateWsLocal = 'ws://127.0.0.1:8000/ws/translate-stream';

  /// Production defaults (deployed Render services).
  ///
  /// You can still override these with `--dart-define`.
  static const String _prodSignalingPlaceholder =
      String.fromEnvironment('LINGUA_SIGNALING_DEFAULT', defaultValue: 'https://linguacall-signal.onrender.com');
  static const String _prodTranslateWsPlaceholder = String.fromEnvironment(
    'LINGUA_TRANSLATE_WS_DEFAULT',
    defaultValue: 'wss://linguacall-api.onrender.com/ws/translate-stream',
  );

  /// Socket.io / HTTP signaling (Node server). Use **https://** on Render.
  static String get signalingHttpUrl {
    const override = String.fromEnvironment('LINGUA_SIGNALING_URL');
    if (override.isNotEmpty) return override;
    if (profile == 'prod') return _prodSignalingPlaceholder;
    return _defaultSignalingLocal;
  }

  /// FastAPI `/ws/translate-stream` endpoints (tried in order). Use **wss://** on Render.
  static List<String> get translationStreamUrls {
    const single = String.fromEnvironment('LINGUA_TRANSLATE_WS');
    if (single.isNotEmpty) return <String>[single];
    if (profile == 'prod') return <String>[_prodTranslateWsPlaceholder];
    return <String>[
      _defaultTranslateWsLocal,
      'ws://10.0.2.2:8000/ws/translate-stream',
    ];
  }

  static void debugLogEndpoints() {
    debugPrint(
      'AppConfig: profile=$profile signaling=$signalingHttpUrl '
      'translate=${translationStreamUrls.join(", ")} '
      'wsTimeout=${translationWsTimeoutSec}s wsRetries=$translationWsRetries',
    );
  }
}
