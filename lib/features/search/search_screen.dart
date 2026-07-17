import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String query = "";
  String selectedType = "All";

  static const types = ["All", "Projects", "Boards", "Photos", "Components"];
  static const results = [
    _SearchResult(
      title: "Azrieli Office Tower",
      subtitle: "3 boards • Schneider • 630A MDB",
      meta: "Completed • 14/04/2026",
      icon: Icons.folder_copy,
      tag: "Projects",
    ),
    _SearchResult(
      title: "Main Distribution Board",
      subtitle: "MDB-2026-021 • Azrieli Office Tower",
      meta: "Rated 630A • 400V",
      icon: Icons.dashboard_customize,
      tag: "Boards",
    ),
    _SearchResult(
      title: "Masterpact MTZ2",
      subtitle: "Main incomer • Schneider Electric",
      meta: "Component • Quantity 1",
      icon: Icons.memory,
      tag: "Components",
    ),
    _SearchResult(
      title: "Single Line Diagram",
      subtitle: "Hospital Project • ATS board",
      meta: "PDF • Updated 10/04/2026",
      icon: Icons.picture_as_pdf,
      tag: "Projects",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleResults = results.where((result) {
      final matchesType = selectedType == "All" || result.tag == selectedType;
      final matchesQuery =
          query.trim().isEmpty ||
          "${result.title} ${result.subtitle} ${result.meta}"
              .toLowerCase()
              .contains(query.toLowerCase());

      return matchesType && matchesQuery;
    }).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
          children: [
            const Text(
              "Search",
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              "Find projects, boards, photos, PDFs and components instantly.",
              style: TextStyle(
                color: Color(0xFFB8BECA),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                hintText: "Search Schneider, 630A, project #...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: types.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final type = types[index];
                  final selected = type == selectedType;

                  return ChoiceChip(
                    label: Text(type),
                    selected: selected,
                    onSelected: (_) => setState(() => selectedType = type),
                    selectedColor: colors.primary,
                    backgroundColor: colors.surface,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFC7CDD8),
                      fontWeight: FontWeight.w800,
                    ),
                    side: BorderSide(
                      color: selected
                          ? colors.primary
                          : const Color(0xFF26303E),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Results",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  "${visibleResults.length}",
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (visibleResults.isEmpty)
              _EmptySearch(colors: colors)
            else
              for (final result in visibleResults) ...[
                _SearchResultCard(result: result),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final _SearchResult result;

  const _SearchResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26303E)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(result.icon, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  result.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8BECA),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  result.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFE4E7EF)),
        ],
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  final ColorScheme colors;

  const _EmptySearch({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26303E)),
      ),
      child: const Column(
        children: [
          Icon(Icons.search_off, size: 38, color: Color(0xFFB8BECA)),
          SizedBox(height: 12),
          Text(
            "No matching records",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            "Try a customer, manufacturer, board type, rating or component.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB8BECA)),
          ),
        ],
      ),
    );
  }
}

class _SearchResult {
  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final String tag;

  const _SearchResult({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.tag,
  });
}
