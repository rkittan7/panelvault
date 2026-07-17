import 'package:flutter/material.dart';

import '../../app/company_context.dart';
import '../../shared/widgets/panelvault_logo.dart';
import '../projects/new_project_screen.dart';

const _line = Color(0xFF26303E);
const _purple = Color(0xFF8B4DFF);
const _orange = Color(0xFFFF7A1A);
const _green = Color(0xFF35E177);
const _blue = Color(0xFF5E78FF);

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: [
            _Header(
              onNewBoard: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NewProjectScreen()),
                );
              },
            ),
            const SizedBox(height: 22),
            const _StatsRow(),
            const SizedBox(height: 22),
            const Divider(color: _line, height: 1),
            const SizedBox(height: 22),
            const _SectionHeading(title: "Board Types"),
            const SizedBox(height: 16),
            const _CategoryGrid(),
            const SizedBox(height: 24),
            const _QuickSearch(),
            const SizedBox(height: 24),
            const Divider(color: _line, height: 1),
            const SizedBox(height: 22),
            const _SectionHeading(title: "Recent Projects"),
            const SizedBox(height: 16),
            const _RecentBoards(),
            const SizedBox(height: 92),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onNewBoard;

  const _Header({required this.onNewBoard});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<bool>(
      valueListenable: contractorModeController,
      builder: (context, contractorMode, _) {
        return Row(
          children: [
            _IconButton(
              icon: Icons.menu_rounded,
              onTap: contractorMode
                  ? () => _showCompanySwitcher(context)
                  : () => _showContractorModeHint(context),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: contractorMode
                  ? ValueListenableBuilder<ContractorCompany?>(
                      valueListenable: activeCompanyController,
                      builder: (context, activeCompany, _) {
                        final title = activeCompany?.name ?? allCompaniesLabel;
                        final subtitle = activeCompany == null
                            ? "Every company in PanelVault"
                            : "Contractor workspace";

                        return _HeaderTitle(title: title, subtitle: subtitle);
                      },
                    )
                  : const _HeaderTitle(
                      title: "PanelVault",
                      subtitle: "Electrical project archive",
                    ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onNewBoard,
              icon: const Icon(Icons.add, size: 18),
              label: const Text("New"),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showContractorModeHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Turn on Contractor Mode in More to switch companies."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showCompanySwitcher(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface.withValues(alpha: 0.98),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: ValueListenableBuilder<ContractorCompany?>(
              valueListenable: activeCompanyController,
              builder: (context, activeCompany, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Companies",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Choose which contractor workspace is active.",
                      style: TextStyle(
                        color: Color(0xFFB8BECA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _CompanySwitchTile(
                      title: allCompaniesLabel,
                      subtitle: "Show every company and project together",
                      color: colors.primary,
                      selected: activeCompany == null,
                      onTap: () {
                        activeCompanyController.value = null;
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    for (final company in contractorCompanies) ...[
                      _CompanySwitchTile(
                        title: company.name,
                        subtitle: "${company.role} • ${company.projectCount}",
                        color: company.color,
                        selected: activeCompany?.name == company.name,
                        onTap: () {
                          activeCompanyController.value = company;
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HeaderTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PanelVaultLogo(size: 32, showName: false),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFB8BECA),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CompanySwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CompanySwitchTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.factory, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB8BECA),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.chevron_right,
              color: selected ? color : const Color(0xFFE4E7EF),
              size: selected ? 20 : 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    const stats = [
      _StatData("Total Projects", "214", Icons.folder_copy, _green, "~"),
      _StatData("Photos", "8426", Icons.photo_library, _blue, ""),
      _StatData("Companies", "19", Icons.factory, _orange, ""),
      _StatData("Customers", "67", Icons.groups_2, _purple, ""),
    ];

    return GridView.builder(
      itemCount: stats.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];

        return _GlassPanel(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(stat.icon, color: stat.color, size: 28),
              const Spacer(),
              Text(
                stat.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stat.value,
                style: TextStyle(
                  color: stat.color,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              if (stat.note.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  stat.note,
                  style: const TextStyle(
                    color: Color(0xFFBDC3CF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;

  const _SectionHeading({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ),
        TextButton(
          onPressed: () {},
          child: const Text(
            "View All",
            style: TextStyle(
              color: Color(0xFFB35CFF),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid();

  @override
  Widget build(BuildContext context) {
    const categories = [
      _CategoryData(
        "MDB",
        "Main Distribution Boards",
        "37",
        Icons.bolt,
        _orange,
      ),
      _CategoryData(
        "MCC",
        "Motor Control Centers",
        "19",
        Icons.settings,
        _green,
      ),
      _CategoryData(
        "ATS",
        "Automatic Transfer Switch",
        "8",
        Icons.sync_alt,
        _purple,
      ),
      _CategoryData(
        "Sub Distribution",
        "Sub Distribution Boards",
        "52",
        Icons.account_tree,
        Color(0xFF18D4E8),
      ),
      _CategoryData(
        "Lighting Boards",
        "Lighting Distribution",
        "25",
        Icons.lightbulb,
        Color(0xFFFFD21E),
      ),
      _CategoryData(
        "Power Boards",
        "Power Distribution",
        "41",
        Icons.power,
        Color(0xFFFF4E5F),
      ),
      _CategoryData(
        "Apartment",
        "Residential Boards",
        "52",
        Icons.home_outlined,
        Color(0xFF1CDDE7),
      ),
      _CategoryData(
        "More Categories",
        "Other Board Types",
        "12+",
        Icons.more_horiz,
        Color(0xFFB8BFCC),
      ),
    ];

    return GridView.builder(
      itemCount: categories.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.18,
      ),
      itemBuilder: (context, index) {
        final category = categories[index];

        return _GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(category.icon, color: category.color, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      category.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB8BECA),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F3A62),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  category.count,
                  style: const TextStyle(
                    color: Color(0xFF75ADFF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickSearch extends StatelessWidget {
  const _QuickSearch();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Quick Search",
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: Icon(Icons.tune, color: colors.primary),
                label: Text(
                  "Advanced Filters",
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: "Search 630A, Schneider, project #...",
              hintStyle: const TextStyle(color: Color(0xFF9EA5B2)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFD3D8E2)),
              filled: true,
              fillColor: colors.surface.withValues(alpha: 0.72),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: _FilterPill(label: "All Types")),
              const SizedBox(width: 8),
              const Expanded(child: _FilterPill(label: "Any Year")),
              const SizedBox(width: 8),
              const Expanded(
                flex: 2,
                child: _FilterPill(label: "All Manufacturers"),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.search),
                label: const Text("Search"),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentBoards extends StatelessWidget {
  const _RecentBoards();

  @override
  Widget build(BuildContext context) {
    const projects = [
      _BoardData(
        "Azrieli Office Tower",
        "3 boards",
        "630A MDB",
        "Schneider",
        "Completed",
        "14/04/2026",
        _green,
      ),
      _BoardData(
        "Tel Aviv Mall",
        "2 boards",
        "400A MCC",
        "ABB",
        "In Progress",
        "12/04/2026",
        Color(0xFF75ADFF),
      ),
      _BoardData(
        "Hospital Project",
        "4 boards",
        "1600A ATS",
        "Schneider",
        "Design",
        "10/04/2026",
        Color(0xFFFFC43D),
      ),
    ];

    return Column(
      children: [
        for (final project in projects) ...[
          _BoardRow(board: project),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BoardRow extends StatelessWidget {
  final _BoardData board;

  const _BoardRow({required this.board});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF59616D), Color(0xFF202733)],
              ),
            ),
            child: const Icon(
              Icons.electrical_services,
              color: Colors.white70,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  board.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  "${board.code} • ${board.rating} • ${board.manufacturer}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFC6CBD5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: board.statusColor.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  board.status,
                  style: TextStyle(
                    color: board.statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                board.date,
                style: const TextStyle(
                  color: Color(0xFFC6CBD5),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Color(0xFFE3E7EF), size: 28),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;

  const _FilterPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassPanel({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String note;

  const _StatData(this.title, this.value, this.icon, this.color, this.note);
}

class _CategoryData {
  final String title;
  final String subtitle;
  final String count;
  final IconData icon;
  final Color color;

  const _CategoryData(
    this.title,
    this.subtitle,
    this.count,
    this.icon,
    this.color,
  );
}

class _BoardData {
  final String title;
  final String code;
  final String rating;
  final String manufacturer;
  final String status;
  final String date;
  final Color statusColor;

  const _BoardData(
    this.title,
    this.code,
    this.rating,
    this.manufacturer,
    this.status,
    this.date,
    this.statusColor,
  );
}
