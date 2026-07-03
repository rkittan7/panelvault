import 'package:flutter/material.dart';

import 'project_details_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Projects"),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text("New Project"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ProjectCard(
            project: "Hospital Expansion",
            board: "Main Distribution Board",
            company: "Schneider Electric",
            customer: "Electra",
            photos: 42,
          ),
          SizedBox(height: 16),
          ProjectCard(
            project: "Airport Terminal",
            board: "ATS Board",
            company: "ABB",
            customer: "Airport Authority",
            photos: 18,
          ),
          SizedBox(height: 16),
          ProjectCard(
            project: "Intel Factory",
            board: "MCC",
            company: "Siemens",
            customer: "Intel",
            photos: 126,
          ),
        ],
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  final String project;
  final String board;
  final String company;
  final String customer;
  final int photos;

  const ProjectCard({
    super.key,
    required this.project,
    required this.board,
    required this.company,
    required this.customer,
    required this.photos,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProjectDetailsScreen(
              projectName: project,
              boardType: board,
              manufacturer: company,
              customer: customer,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B1F27),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Container(
              height: 180,
              decoration: const BoxDecoration(
                color: Color(0xFF2A2F3A),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.photo_camera,
                  size: 60,
                  color: Colors.grey,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(board),
                  Text(company),
                  Text(customer),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.photo, size: 18),
                      const SizedBox(width: 8),
                      Text("$photos Photos"),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}