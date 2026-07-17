import 'package:flutter/material.dart';

class NewProjectScreen extends StatefulWidget {
  const NewProjectScreen({super.key});

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final projectController = TextEditingController();
  final customerController = TextEditingController();

  String boardType = "Main Distribution Board";
  String manufacturer = "Schneider Electric";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Project")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Project Information",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 25),

          TextField(
            controller: projectController,
            decoration: const InputDecoration(
              labelText: "Project Name",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: customerController,
            decoration: const InputDecoration(
              labelText: "Customer",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 20),

          DropdownButtonFormField<String>(
            initialValue: boardType,
            decoration: const InputDecoration(
              labelText: "Board Type",
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: "Main Distribution Board",
                child: Text("Main Distribution Board"),
              ),
              DropdownMenuItem(
                value: "MCC",
                child: Text("Motor Control Center"),
              ),
              DropdownMenuItem(value: "ATS", child: Text("ATS Board")),
              DropdownMenuItem(
                value: "Lighting",
                child: Text("Lighting Board"),
              ),
            ],
            onChanged: (value) {
              setState(() {
                boardType = value!;
              });
            },
          ),

          const SizedBox(height: 20),

          DropdownButtonFormField<String>(
            initialValue: manufacturer,
            decoration: const InputDecoration(
              labelText: "Manufacturer",
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: "Schneider Electric",
                child: Text("Schneider Electric"),
              ),
              DropdownMenuItem(value: "ABB", child: Text("ABB")),
              DropdownMenuItem(value: "Siemens", child: Text("Siemens")),
              DropdownMenuItem(value: "Eaton", child: Text("Eaton")),
            ],
            onChanged: (value) {
              setState(() {
                manufacturer = value!;
              });
            },
          ),

          const SizedBox(height: 35),

          SizedBox(
            height: 55,
            child: FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text("Continue"),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
