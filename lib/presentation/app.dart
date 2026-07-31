import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import 'screens/home/home_screen.dart';

class LocalBridgeApp extends StatelessWidget {
  const LocalBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff00796b);
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: const HomeScreen(),
    );
  }
}
