import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/radio_browser_client.dart';
import 'data/radio_top_store.dart';
import 'models/station.dart';
import 'ui/radio_home_page.dart';

void main() {
  MediaKit.ensureInitialized();
  runApp(const RadioTopApp());
}

class RadioTopApp extends StatefulWidget {
  const RadioTopApp({super.key});

  @override
  State<RadioTopApp> createState() => _RadioTopAppState();
}

class _RadioTopAppState extends State<RadioTopApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RadioTop',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB7F36B),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF42651B),
          onPrimary: Colors.white,
          secondary: const Color(0xFF42651B),
          onSecondary: Colors.white,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101211),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB7F36B),
          brightness: Brightness.dark,
          surface: const Color(0xFF171A18),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: RadioHomePage(
        client: RadioBrowserClient(),
        store: RadioTopStore(),
        favorites: StationFavorites(),
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}
