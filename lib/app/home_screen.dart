import 'package:flutter/material.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/companies/company_screen.dart';
import '../features/projects/new_project_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  int selectedIndex = 0;

  final pages = const [

    DashboardScreen(),

    ProjectsScreen(),

    NewProjectScreen(),

    CompanyScreen(),

    SettingsScreen(),

  ];

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      body: pages[selectedIndex],

      bottomNavigationBar: NavigationBar(

        selectedIndex: selectedIndex,

        onDestinationSelected: (value){

          setState(() {

            selectedIndex = value;

          });

        },

        destinations: const [

          NavigationDestination(
            icon: Icon(Icons.home),
            label: "Home",
          ),

          NavigationDestination(
            icon: Icon(Icons.folder),
            label: "Projects",
          ),

          NavigationDestination(
            icon: Icon(Icons.add_box),
            label: "New",
          ),

          NavigationDestination(
            icon: Icon(Icons.business),
            label: "Companies",
          ),

          NavigationDestination(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),

        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {

  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: const Text("Settings"),

      ),

      body: const Center(

        child: Text(

          "PanelVault Settings",

          style: TextStyle(

            fontSize: 28,

            fontWeight: FontWeight.bold,

          ),

        ),

      ),

    );

  }

}