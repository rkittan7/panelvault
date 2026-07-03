import 'package:flutter/material.dart';

class ProjectDetailsScreen extends StatelessWidget {
  final String projectName;
  final String boardType;
  final String manufacturer;
  final String customer;

  const ProjectDetailsScreen({
    super.key,
    required this.projectName,
    required this.boardType,
    required this.manufacturer,
    required this.customer,
  });

  Widget infoCard(
    IconData icon,
    String title,
    String value,
  ) {
    return Card(
      color: const Color(0xFF1B1F27),
      child: ListTile(
        leading: Icon(
          icon,
          color: Colors.orange,
        ),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(projectName),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.camera_alt),
        label: const Text("Add Photos"),
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),

        children: [

          Container(
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF1B1F27),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(
                Icons.photo_library,
                size: 80,
                color: Colors.grey,
              ),
            ),
          ),

          const SizedBox(height: 25),

          infoCard(
            Icons.electrical_services,
            "Board Type",
            boardType,
          ),

          infoCard(
            Icons.business,
            "Manufacturer",
            manufacturer,
          ),

          infoCard(
            Icons.person,
            "Customer",
            customer,
          ),

          infoCard(
            Icons.calendar_month,
            "Build Date",
            "Not Added",
          ),

          infoCard(
            Icons.description,
            "Notes",
            "No Notes",
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.picture_as_pdf),
            label: const Padding(
              padding: EdgeInsets.all(15),
              child: Text("Attach PDF Drawing"),
            ),
          ),

          const SizedBox(height: 15),

          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit),
            label: const Padding(
              padding: EdgeInsets.all(15),
              child: Text("Edit Project"),
            ),
          ),

          const SizedBox(height: 120),
        ],
      ),
    );
  }
}