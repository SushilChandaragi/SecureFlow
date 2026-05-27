/// Dashboard Screen — secure home view, vertical layout (§2)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../services/vault_provider.dart';
import '../widgets/tactical_label.dart';
import '../widgets/sf_badge.dart';
import '../widgets/nav_pill.dart';
import 'password_vault_screen.dart';
import 'authenticator_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  NavTab _currentTab = NavTab.vault;
  Timer? _sessionTimer;
  String _sessionTime = '00:00:00';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(credentialProvider.notifier).load();
      ref.read(totpProvider.notifier).load();
    });
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final profile = ref.read(sessionProvider).profile;
      if (profile != null) {
        setState(() => _sessionTime = profile.sessionDuration);
      }
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
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
        return _VaultHome(sessionTime: _sessionTime);
      case NavTab.keys:
        return const PasswordVaultScreen();
      case NavTab.shield:
        return const AuthenticatorScreen();
      case NavTab.gear:
        return const SettingsScreen();
    }
  }
}

// ─── Vault Home — clean vertical layout, no bento grid ───────────────────────

class _VaultHome extends ConsumerWidget {
  final String sessionTime;
  const _VaultHome({required this.sessionTime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files   = ref.watch(vaultFilesProvider);
    final creds   = ref.watch(credentialProvider);
    final totps   = ref.watch(totpProvider);
    final session = ref.watch(sessionProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          SFSpacing.base, SFSpacing.md, SFSpacing.base, 110),
      children: [

        // ── Top status bar ────────────────────────────────────────────
        Row(
          children: [
            _GlyphBox(),
            const SizedBox(width: SFSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TacticalLabel('ENCLAVE ACTIVE', color: SFColors.success),
                  Text(sessionTime,
                      style: SFTypography.terminal.copyWith(fontSize: 10)),
                ],
              ),
            ),
            const SFBadge('RAM-ONLY',
                color: SFColors.success, background: SFColors.successMuted),
          ],
        ),

        const SizedBox(height: SFSpacing.xl),

        // ── Section: HEADLINE ─────────────────────────────────────────
        Text('SECUREFLOW', style: SFTypography.h1),
        const SizedBox(height: 4),
        Text(
          'Zero-knowledge enclave · Hardware-tethered',
          style: SFTypography.terminal.copyWith(fontSize: 11),
        ),

        const SizedBox(height: SFSpacing.xl),
        _Divider(),

        // ── Stats row ─────────────────────────────────────────────────
        const SizedBox(height: SFSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'CREDENTIALS',
                value: '${creds.length}',
                icon: Icons.key_outlined,
              ),
            ),
            _VerticalDivider(),
            Expanded(
              child: _StatTile(
                label: 'TOTP KEYS',
                value: '${totps.length}',
                icon: Icons.shield_outlined,
              ),
            ),
            _VerticalDivider(),
            Expanded(
              child: files.when(
                data: (list) => _StatTile(
                  label: 'VAULT FILES',
                  value: '${list.length}',
                  icon: Icons.lock_outline,
                ),
                loading: () => const _StatTile(
                  label: 'VAULT FILES',
                  value: '—',
                  icon: Icons.lock_outline,
                ),
                error: (_, __) => const _StatTile(
                  label: 'VAULT FILES',
                  value: 'ERR',
                  icon: Icons.lock_outline,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: SFSpacing.lg),
        _Divider(),
        const SizedBox(height: SFSpacing.xl),

        // ── Section: AUTH METHOD ──────────────────────────────────────
        const _SectionHeader('AUTHENTICATION'),
        const SizedBox(height: SFSpacing.md),
        _InfoRow(
          label: 'METHOD',
          value: session.profile?.authMethodLabel ?? '—',
          icon: Icons.fingerprint,
        ),
        const SizedBox(height: SFSpacing.sm),
        _InfoRow(
          label: 'SESSION ID',
          value: session.profile?.sessionId ?? '—',
          icon: Icons.tag,
          mono: true,
        ),

        const SizedBox(height: SFSpacing.xl),
        _Divider(),
        const SizedBox(height: SFSpacing.xl),

        // ── Section: CLOUD VAULT ──────────────────────────────────────
        const _SectionHeader('CLOUD VAULT'),
        const SizedBox(height: SFSpacing.md),
        _CloudStatusCard(files: files),

        const SizedBox(height: SFSpacing.xl),
        _Divider(),
        const SizedBox(height: SFSpacing.xl),

        // ── Section: SECURITY STATUS ──────────────────────────────────
        const _SectionHeader('SECURITY STATUS'),
        const SizedBox(height: SFSpacing.md),
        _SecurityStatusList(),

        const SizedBox(height: SFSpacing.xl),
      ],
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _GlyphBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: SFColors.bgCard,
        borderRadius: BorderRadius.circular(SFRadius.small),
        border: Border.all(color: SFColors.borderSoft),
      ),
      child: const Center(
        child: Text('SF',
            style: TextStyle(
                color: SFColors.textMuted, fontSize: 11, letterSpacing: 2)),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: SFColors.borderSoft);
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 56, color: SFColors.borderSoft,
      margin: const EdgeInsets.symmetric(horizontal: SFSpacing.xs),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return TacticalLabel(text, color: SFColors.textFaint);
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: SFColors.textFaint),
        const SizedBox(height: 8),
        Text(value,
            style: SFTypography.dataValue.copyWith(fontSize: 28),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        TacticalLabel(label, color: SFColors.textFaint),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool mono;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: SFColors.textFaint),
        const SizedBox(width: SFSpacing.sm),
        TacticalLabel(label, color: SFColors.textFaint),
        const Spacer(),
        Text(
          value,
          style: mono
              ? SFTypography.terminal.copyWith(fontSize: 11)
              : SFTypography.body.copyWith(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CloudStatusCard extends StatelessWidget {
  final AsyncValue<List<dynamic>> files;
  const _CloudStatusCard({required this.files});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SFSpacing.md),
      decoration: BoxDecoration(
        color: SFColors.bgCard,
        borderRadius: BorderRadius.circular(SFRadius.card),
        border: Border.all(color: SFColors.borderSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 20, color: SFColors.textMuted),
          const SizedBox(width: SFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GHOST WAREHOUSE', style: SFTypography.body.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                files.when(
                  data: (list) => Text(
                    list.isEmpty ? 'No assets stored' : '${list.length} encrypted asset(s)',
                    style: SFTypography.bodyMuted.copyWith(fontSize: 11),
                  ),
                  loading: () => Text('Connecting...', style: SFTypography.bodyMuted.copyWith(fontSize: 11)),
                  error: (_, __) => Text('Offline mode',
                      style: SFTypography.bodyMuted.copyWith(fontSize: 11, color: SFColors.textFaint)),
                ),
              ],
            ),
          ),
          const SFBadge('AES-256'),
        ],
      ),
    );
  }
}

class _SecurityStatusList extends StatelessWidget {
  static const _items = [
    (Icons.memory_outlined,      'RAM-ONLY OPERATION',   'No sensitive data on disk'),
    (Icons.enhanced_encryption,  'AES-256-GCM ACTIVE',   'Hardware-grade encryption'),
    (Icons.fingerprint,          'BIOMETRIC BOUND',       'Fingerprint authentication'),
    (Icons.nfc,                  'NFC HARDWARE KEY',      'Physical token required'),
    (Icons.timer_outlined,       'AUTO-LOCK ENABLED',     '5-minute inactivity timeout'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(_items.length, (i) {
        final item = _items[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < _items.length - 1 ? SFSpacing.sm : 0),
          child: Row(
            children: [
              Icon(item.$1, size: 14, color: SFColors.textFaint),
              const SizedBox(width: SFSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.$2, style: SFTypography.body.copyWith(fontSize: 12)),
                    Text(item.$3,
                        style: SFTypography.bodyMuted.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              const Icon(Icons.check_circle_outline,
                  size: 14, color: SFColors.success),
            ],
          ),
        );
      }),
    );
  }
}
