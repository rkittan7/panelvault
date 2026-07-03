import 'package:flutter/material.dart';

import '../boards/new_board_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NewBoardScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("New Board"),
      ),

      appBar: AppBar(
        title: const Text(
          "Electrical Boards",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),

        children: [

          const Text(
            "Good Evening 👋",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            "Ready to build?",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 25),

          TextField(
            decoration: InputDecoration(
              hintText: "Search boards...",
              prefixIcon: const Icon(Icons.search),

              filled: true,
              fillColor: const Color(0xff1B1F27),

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 25),

          const Text(
            "Overview",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          Row(
            children: [

              Expanded(
                child: _StatCard(
                  title: "Boards",
                  value: "214",
                  icon: Icons.electrical_services,
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: _StatCard(
                  title: "Photos",
                  value: "8426",
                  icon: Icons.photo_library,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          const Text(
            "Categories",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 15,
            crossAxisSpacing: 15,
            childAspectRatio: 1.25,

            children: const [

              _CategoryCard("MDB", Icons.bolt),

              _CategoryCard("MCC", Icons.settings),

              _CategoryCard("ATS", Icons.sync),

              _CategoryCard("Lighting", Icons.lightbulb),

              _CategoryCard("Power", Icons.power),

              _CategoryCard("Solar", Icons.sunny),

            ],
          ),

          const SizedBox(height: 30),

          const Text(
            "Recent Projects",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          Card(
            color: const Color(0xff1B1F27),

            child: ListTile(
              leading: const Icon(Icons.folder),
              title: const Text("No projects yet"),
              subtitle: const Text("Tap 'New Board' to create your first project."),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: const Color(0xff1B1F27),
        borderRadius: BorderRadius.circular(18),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Icon(icon,size:30),

          const SizedBox(height:20),

          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),

          Text(title),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final IconData icon;

  const _CategoryCard(this.title,this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff1B1F27),
        borderRadius: BorderRadius.circular(18),
      ),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [

          Icon(icon,size:34),

          const SizedBox(height:10),

          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          )
        ],
      ),
    );
  }
}