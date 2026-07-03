import 'package:flutter/material.dart';

import '../companies/company_screen.dart';

class NewBoardScreen extends StatelessWidget {
  const NewBoardScreen({super.key});

  static const List<Map<String, dynamic>> boardTypes = [
    {"title": "Main Distribution Board", "icon": Icons.bolt},
    {"title": "Sub Distribution Board", "icon": Icons.electrical_services},
    {"title": "Motor Control Center (MCC)", "icon": Icons.settings},
    {"title": "ATS Board", "icon": Icons.sync},
    {"title": "Lighting Board", "icon": Icons.lightbulb},
    {"title": "Power Board", "icon": Icons.power},
    {"title": "Generator Board", "icon": Icons.generating_tokens},
    {"title": "Solar Board", "icon": Icons.sunny},
    {"title": "UPS Board", "icon": Icons.battery_charging_full},
    {"title": "Fire Pump Board", "icon": Icons.local_fire_department},
    {"title": "EV Charging Board", "icon": Icons.ev_station},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Project"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Step 1 of 5",
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          const Text(
            "What are you building?",
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 30),

          ...boardTypes.map(
            (board) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                color: const Color(0xff1B1F27),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: Icon(
                    board["icon"],
                    size: 34,
                    color: Colors.orange,
                  ),
                  title: Text(
                    board["title"],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CompanyScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Add Custom Board Type"),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}