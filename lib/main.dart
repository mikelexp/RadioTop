import 'package:flutter/material.dart';

import 'data/radio_browser_client.dart';
import 'data/radio_top_store.dart';
import 'models/station.dart';
import 'ui/radio_home_page.dart';

void main() {
  runApp(const RadioTopApp());
}

class RadioTopApp extends StatelessWidget {
  const RadioTopApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101211);
    return MaterialApp(
      title: 'RadioTop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
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
      ),
    );
  }
}
