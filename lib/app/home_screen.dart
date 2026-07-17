import 'package:flutter/material.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/more/more_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/projects/new_project_screen.dart';
import '../features/search/search_screen.dart';

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
    SearchScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) {
          setState(() {
            selectedIndex = value;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: "Dashboard"),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: "Projects",
          ),
          NavigationDestination(icon: Icon(Icons.add), label: "New Project"),
          NavigationDestination(icon: Icon(Icons.search), label: "Search"),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: "More"),
        ],
      ),
    );
  }
}
