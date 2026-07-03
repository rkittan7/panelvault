import 'package:flutter/material.dart';

import 'add_company_screen.dart';

class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key});

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  final TextEditingController searchController = TextEditingController();

  final List<String> companies = [
    "Schneider Electric",
    "ABB",
    "Siemens",
    "Eaton",
    "Noark",
    "LS Electric",
    "Chint",
  ];

  List<String> filteredCompanies = [];

  @override
  void initState() {
    super.initState();

    filteredCompanies = List.from(companies);

    searchController.addListener(() {
      filterCompanies(searchController.text);
    });
  }

  void filterCompanies(String text) {
    setState(() {
      filteredCompanies = companies
          .where(
            (company) =>
                company.toLowerCase().contains(text.toLowerCase()),
          )
          .toList();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text("Add Company"),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddCompanyScreen(),
            ),
          );

          setState(() {});
        },
      ),

      appBar: AppBar(
        title: const Text("Manufacturers"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [

            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search manufacturers...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xff1B1F27),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: filteredCompanies.length,
                itemBuilder: (context, index) {
                  final company = filteredCompanies[index];

                  return Card(
                    color: const Color(0xff1B1F27),

                    margin: const EdgeInsets.only(bottom: 12),

                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade700,
                        child: Text(
                          company[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      title: Text(company),

                      subtitle: const Text("Tap to select"),

                      trailing: const Icon(Icons.chevron_right),

                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("$company selected"),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}