import 'package:flutter/material.dart';

import 'home_screen.dart';

class PanelApp extends StatelessWidget {

  const PanelApp({super.key});

  @override
  Widget build(BuildContext context) {

    return MaterialApp(

      debugShowCheckedModeBanner: false,

      title: "PanelVault",

      themeMode: ThemeMode.dark,

      darkTheme: ThemeData(

        brightness: Brightness.dark,

        useMaterial3: true,

        scaffoldBackgroundColor: const Color(0xff0F1115),

        colorScheme: ColorScheme.fromSeed(

          seedColor: Colors.orange,

          brightness: Brightness.dark,

        ),

      ),

      home: const HomeScreen(),

    );

  }

}