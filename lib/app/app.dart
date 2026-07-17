import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'home_screen.dart';

class PanelApp extends StatelessWidget {
  const PanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PanelTheme>(
      valueListenable: panelThemeController,
      builder: (context, panelTheme, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: "PanelVault",
          themeMode: ThemeMode.dark,
          darkTheme: panelTheme.toThemeData(),
          home: const HomeScreen(),
        );
      },
    );
  }
}
