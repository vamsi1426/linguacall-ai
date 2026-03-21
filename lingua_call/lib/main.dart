import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

import 'package:linguacall/utils/theme.dart';
import 'package:linguacall/services/auth_service.dart';
import 'package:linguacall/services/call_state_service.dart';
import 'package:linguacall/services/signaling_service.dart';
import 'package:linguacall/services/ai_translation_service.dart';
import 'package:linguacall/services/realtime_call_coordinator.dart';
import 'package:linguacall/config/app_config.dart';
import 'package:linguacall/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  AppConfig.debugLogEndpoints();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CallStateService()),
        ChangeNotifierProvider(create: (_) => SignalingService()),
        ChangeNotifierProvider(create: (_) => AITranslationService()),
      ],
      child: ChangeNotifierProvider(
        create: (ctx) => RealtimeCallCoordinator(
          signaling: ctx.read<SignalingService>(),
          translation: ctx.read<AITranslationService>(),
          callState: ctx.read<CallStateService>(),
        ),
        child: const LinguaCallApp(),
      ),
    ),
  );
}

class LinguaCallApp extends StatelessWidget {
  const LinguaCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinguaCall AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}

