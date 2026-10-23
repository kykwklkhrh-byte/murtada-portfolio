import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/app_shell.dart';

defaultAppTheme() {
  const midnight = Color(0xFF0C1726);
  const panel = Color(0xFF13243A);
  const emerald = Color(0xFF22C987);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: midnight,
    colorScheme: ColorScheme.fromSeed(seedColor: emerald, brightness: Brightness.dark).copyWith(
      primary: emerald,
      surface: panel,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: midnight, foregroundColor: Colors.white, elevation: 0),
    cardTheme: CardThemeData(color: panel, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22)))),
  );
}

class MurtadaStarApp extends StatelessWidget {
  const MurtadaStarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مرتضى ستار',
      debugShowCheckedModeBanner: false,
      theme: defaultAppTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: const Directionality(textDirection: TextDirection.rtl, child: AppShell()),
    );
  }
}

void main() => runApp(const MurtadaStarApp());
