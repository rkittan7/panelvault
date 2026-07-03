import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AddCompanyScreen extends StatefulWidget {
  const AddCompanyScreen({super.key});

  @override
  State<AddCompanyScreen> createState() => _AddCompanyScreenState();
}

class _AddCompanyScreenState extends State<AddCompanyScreen> {
  final TextEditingController companyController = TextEditingController();

  final ImagePicker picker = ImagePicker();

  XFile? image;

  Future<void> pickLogo() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (picked != null) {
      setState(() {
        image = picked;
      });
    }
  }

  @override
  void dispose() {
    companyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Manufacturer"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: pickLogo,
              child: CircleAvatar(
                radius: 55,
                backgroundColor: Colors.orange,
                backgroundImage:
                    image == null ? null : FileImage(File(image!.path)),
                child: image == null
                    ? const Icon(
                        Icons.camera_alt,
                        color: Colors.black,
                        size: 35,
                      )
                    : null,
              ),
            ),
          ),

          const SizedBox(height: 25),

          TextField(
            controller: companyController,
            decoration: InputDecoration(
              labelText: "Manufacturer Name",
              hintText: "Example: Schneider Electric",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          const SizedBox(height: 30),

          SizedBox(
            height: 55,
            child: FilledButton.icon(
              onPressed: () {
                if (companyController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Please enter a company name."),
                    ),
                  );
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "${companyController.text} saved successfully.",
                    ),
                  ),
                );

                Navigator.pop(context);
              },
              icon: const Icon(Icons.save),
              label: const Text(
                "Save Manufacturer",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),

          const SizedBox(height: 15),

          const Center(
            child: Text(
              "Database support will be added in the next version.",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}