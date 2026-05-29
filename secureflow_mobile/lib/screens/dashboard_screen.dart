/// Dashboard Screen — secure home view, vertical layout (§2)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../models/vault_document.dart';
import '../services/vault_provider.dart';
import '../widgets/bento_card.dart';
import '../widgets/tactical_label.dart';
import '../widgets/nav_pill.dart';
import 'password_vault_screen.dart';
import 'authenticator_screen.dart';
import 'document_vault_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  NavTab _currentTab = NavTab.vault;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(credentialProvider.notifier).load();
      ref.read(totpProvider.notifier).load();
      ref.read(documentProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      body: Stack(
        children: [
          SafeArea(child: _buildCurrentScreen()),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: NavPill(
                current: _currentTab,
                onTabChanged: (tab) => setState(() => _currentTab = tab),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentTab) {
      case NavTab.vault:
        return _VaultHome(onNavigate: (tab) => setState(() => _currentTab = tab));
      case NavTab.keys:
        return const PasswordVaultScreen();
      case NavTab.shield:
        return const AuthenticatorScreen();
      case NavTab.folder:
        return const DocumentVaultScreen();
      case NavTab.gear:
        return const SettingsScreen();
    }
  }
}

// ─── Vault Home ───────────────────────────────────────────────────────────────

class _VaultHome extends ConsumerWidget {
  final ValueChanged<NavTab> onNavigate;
  const _VaultHome({required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds      = ref.watch(credentialProvider);
    final totps      = ref.watch(totpProvider);
    final docs       = ref.watch(documentProvider);
    final session    = ref.watch(sessionProvider);
    final syncedDocs = docs.where((d) => d.isSynced).length;
    final recentDocs = [...docs]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recent = recentDocs.take(3).toList();
    final syncedLabel = docs.isEmpty ? '0' : '$syncedDocs / ${docs.length}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          SFSpacing.base, SFSpacing.md, SFSpacing.base, 110),
      children: [
        const TacticalLabel('VAULT OVERVIEW', color: SFColors.textMuted),
        const SizedBox(height: 6),
        Text('SECUREFLOW', style: SFTypography.h1),

        const SizedBox(height: SFSpacing.xl),
        _SessionCard(session: session),

        const SizedBox(height: SFSpacing.lg),
        const _SectionHeader('OVERVIEW'),
        const SizedBox(height: SFSpacing.sm),
        _MetricGrid(
          items: [
            _MetricItem(
              label: 'PASSWORDS',
              value: '${creds.length}',
              icon: Icons.key_outlined,
            ),
            _MetricItem(
              label: 'MFA CODES',
              value: '${totps.length}',
              icon: Icons.shield_outlined,
            ),
            _MetricItem(
              label: 'DOCUMENTS',
              value: '${docs.length}',
              icon: Icons.folder_outlined,
            ),
            _MetricItem(
              label: 'SYNCED',
              value: syncedLabel,
              icon: Icons.cloud_done_outlined,
            ),
          ],
        ),

        const SizedBox(height: SFSpacing.lg),
        const _SectionHeader('QUICK ACTIONS'),
        const SizedBox(height: SFSpacing.sm),
        _ActionGrid(
          actions: [
            _ActionItem(
              label: 'PASSWORDS',
              icon: Icons.key_outlined,
              tab: NavTab.keys,
            ),
            _ActionItem(
              label: 'MFA CODES',
              icon: Icons.shield_outlined,
              tab: NavTab.shield,
            ),
            _ActionItem(
              label: 'DOCUMENTS',
              icon: Icons.folder_outlined,
              tab: NavTab.folder,
            ),
            _ActionItem(
              label: 'SETTINGS',
              icon: Icons.settings_outlined,
              tab: NavTab.gear,
            ),
          ],
          onNavigate: onNavigate,
        ),

        const SizedBox(height: SFSpacing.lg),
        const _SectionHeader('RECENT DOCUMENTS'),
        const SizedBox(height: SFSpacing.sm),
        if (docs.isEmpty)
          BentoCard(
            child: Text(
              'No documents stored yet.',
              style: SFTypography.bodyMuted,
            ),
          )
        else
          BentoCard(
            padding: const EdgeInsets.symmetric(
              horizontal: SFSpacing.md,
              vertical: SFSpacing.sm,
            ),
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  _DocRow(doc: recent[i]),
                  if (i != recent.length - 1)
                    const Divider(
                      color: SFColors.borderSoft,
                      height: SFSpacing.lg,
                    ),
                ],
              ],
            ),
          ),

        const SizedBox(height: SFSpacing.xl),
      ],
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return TacticalLabel(text, color: SFColors.textFaint);
  }
}

class _SessionCard extends StatelessWidget {
  final SessionState session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final statusText = session.isUnlocked ? 'ACTIVE' : 'LOCKED';
    final statusColor = session.isUnlocked ? SFColors.success : SFColors.textFaint;

    return BentoCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                session.isUnlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                size: 16,
                color: SFColors.textMuted,
              ),
              const SizedBox(width: SFSpacing.sm),
              const TacticalLabel('VAULT STATUS', color: SFColors.textFaint),
              const Spacer(),
              Text(
                statusText,
                style: SFTypography.metadata.copyWith(color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: SFSpacing.md),
          _InfoRow('AUTH METHOD', session.profile?.authMethodLabel ?? '—'),
          _InfoRow('SESSION TIME', session.profile?.sessionDuration ?? '—'),
          _InfoRow(
            'SESSION ID',
            session.profile?.sessionId ?? '—',
            mono: true,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _InfoRow(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: SFTypography.metadata.copyWith(fontSize: 10)),
          const Spacer(),
          Text(
            value,
            style: mono
                ? SFTypography.terminal.copyWith(fontSize: 11)
                : SFTypography.body.copyWith(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final IconData icon;
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricItem> items;
  const _MetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - SFSpacing.base) / 2;
        return Wrap(
          spacing: SFSpacing.base,
          runSpacing: SFSpacing.base,
          children: items
              .map((item) => SizedBox(
                    width: tileWidth,
                    child: _MetricCard(item: item),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _MetricItem item;
  const _MetricCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 18, color: SFColors.textFaint),
          const SizedBox(height: SFSpacing.sm),
          Text(item.value, style: SFTypography.dataValue),
          const SizedBox(height: 4),
          TacticalLabel(item.label, color: SFColors.textFaint),
        ],
      ),
    );
  }
}

class _ActionItem {
  final String label;
  final IconData icon;
  final NavTab tab;
  const _ActionItem({
    required this.label,
    required this.icon,
    required this.tab,
  });
}

class _ActionGrid extends StatelessWidget {
  final List<_ActionItem> actions;
  final ValueChanged<NavTab> onNavigate;
  const _ActionGrid({required this.actions, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - SFSpacing.base) / 2;
        return Wrap(
          spacing: SFSpacing.base,
          runSpacing: SFSpacing.base,
          children: actions
              .map((action) => SizedBox(
                    width: tileWidth,
                    child: _ActionCard(
                      action: action,
                      onNavigate: onNavigate,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final _ActionItem action;
  final ValueChanged<NavTab> onNavigate;
  const _ActionCard({required this.action, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      onTap: () => onNavigate(action.tab),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SFColors.bgElevated,
              borderRadius: BorderRadius.circular(SFRadius.small),
              border: Border.all(color: SFColors.borderSoft),
            ),
            child: Icon(action.icon, size: 18, color: SFColors.textMuted),
          ),
          const SizedBox(width: SFSpacing.sm),
          Expanded(
            child: Text(action.label, style: SFTypography.body),
          ),
          const Icon(Icons.chevron_right, size: 16, color: SFColors.textFaint),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final VaultDocument doc;
  const _DocRow({required this.doc});

  IconData get _icon {
    if (doc.isPdf) return Icons.picture_as_pdf_outlined;
    if (doc.isImage) return Icons.image_outlined;
    if (doc.isText) return Icons.text_snippet_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: SFColors.bgElevated,
            borderRadius: BorderRadius.circular(SFRadius.small),
            border: Border.all(color: SFColors.borderSoft),
          ),
          child: Icon(_icon, size: 18, color: SFColors.textMuted),
        ),
        const SizedBox(width: SFSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                doc.name,
                style: SFTypography.body.copyWith(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                doc.sizeLabel,
                style: SFTypography.bodyMuted.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
        _StatusPill(label: doc.isSynced ? 'SYNCED' : 'LOCAL'),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SFColors.bgElevated,
        borderRadius: BorderRadius.circular(SFRadius.pill),
        border: Border.all(color: SFColors.borderSoft),
      ),
      child: Text(
        label,
        style: SFTypography.metadata.copyWith(fontSize: 9),
      ),
    );
  }
}

