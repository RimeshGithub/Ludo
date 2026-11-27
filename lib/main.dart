import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ludo/ludo.dart';
import 'firebase_options.dart';

/// Stand-alone launcher for the Ludo mode (Android + Windows).
/// Online play needs Firebase; without it every other mode still works.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // After `flutterfire configure`, pass options: DefaultFirebaseOptions.currentPlatform.
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase not configured, online mode disabled: $e');
  }
  runApp(const ProviderScope(child: LudoApp()));
}

class LudoApp extends StatelessWidget {
  const LudoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo',
      scrollBehavior: const NoScrollbarBehavior(),
      debugShowCheckedModeBanner: false,
      theme: LudoTheme.dark(),
      home: const LudoHomeScreen(),
    );
  }
}

class NoScrollbarBehavior extends MaterialScrollBehavior {
  const NoScrollbarBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child; // no scrollbar anywhere
  }
}