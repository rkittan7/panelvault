import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../app/company_context.dart';
import '../../shared/widgets/panelvault_logo.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF26303E)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PanelVaultLogo(size: 54),
                  SizedBox(height: 12),
                  Text(
                    "Electrical project archive",
                    style: TextStyle(
                      color: Color(0xFFB8BECA),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<bool>(
              valueListenable: contractorModeController,
              builder: (context, contractorMode, _) {
                return _ContractorModeCard(
                  enabled: contractorMode,
                  onChanged: (value) {
                    contractorModeController.value = value;
                    if (value && activeCompanyController.value == null) {
                      activeCompanyController.value = contractorCompanies.first;
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 22),
            const Text(
              "Themes",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<PanelTheme>(
              valueListenable: panelThemeController,
              builder: (context, selectedTheme, _) {
                return Column(
                  children: [
                    for (final theme in panelThemes) ...[
                      _ThemeOption(
                        theme: theme,
                        selected: selectedTheme.name == theme.name,
                        onTap: () => panelThemeController.value = theme,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            const Text(
              "Archive",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const _MoreTile(
              icon: Icons.business,
              title: "All Companies",
              subtitle: "Contractor workspaces, manufacturers and factories",
            ),
            const _MoreTile(
              icon: Icons.groups_2,
              title: "Customers",
              subtitle: "Contacts, addresses and related projects",
            ),
            const _MoreTile(
              icon: Icons.cloud_upload,
              title: "Backups",
              subtitle: "Export and protect the archive",
            ),
            const _MoreTile(
              icon: Icons.qr_code_2,
              title: "QR Codes",
              subtitle: "Future board labels and quick access",
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractorModeCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ContractorModeCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.badge_outlined, color: colors.primary, size: 21),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Contractor Mode",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  "Switch between companies from the dashboard menu.",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFB8BECA),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final PanelTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.primary.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            _ThemeSwatch(theme: theme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    theme.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB8BECA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? theme.primary : const Color(0xFF8D95A3),
              size: 21,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final PanelTheme theme;

  const _ThemeSwatch({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Row(
          children: [
            Expanded(child: ColoredBox(color: theme.background)),
            Expanded(child: ColoredBox(color: theme.primary)),
            Expanded(child: ColoredBox(color: theme.secondary)),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8BECA),
                    fontWeight: FontWeight.w600,
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
