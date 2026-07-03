import 'package:flutter/material.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xff1B1F27),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.menu),
        ),

        const SizedBox(width: 18),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Row(
                children: [
                  Icon(
                    Icons.bolt,
                    color: Colors.orange,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "PanelVault",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                "Distribution Boards",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),

        FilledButton.icon(
          onPressed: null,
          icon: Icon(Icons.add),
          label: Text("New Board"),
        ),
      ],
    );
  }
}