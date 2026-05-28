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
import 'document_vault_screen.dart';
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
      ref.read(documentProvider.notifier).load();
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
      case NavTab.folder:
        return const DocumentVaultScreen();
      case NavTab.gear:
        return const SettingsScreen();
    }
  }
}

// ─── Vault Home ───────────────────────────────────────────────────────────────

class _VaultHome extends ConsumerWidget {
  final String sessionTime;
  const _VaultHome({required this.sessionTime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(vaultFilesProvider);
    final creds      = ref.watch(credentialProvider);
    final totps      = ref.watch(totpProvider);
    final docs       = ref.watch(documentProvider);
    final session    = ref.watch(sessionProvider);

    // Derived values from live data
    final cloudCount = filesAsync.valueOrNull?.length ?? 0;
    final cloudError = filesAsync.hasError;
    final cloudLoading = filesAsync.isLoading;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          SFSpacing.base, SFSpacing.md, SFSpacing.base, 110),
      children: [

        // ── Status bar ────────────────────────────────────────────────
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
          ],
        ),

        const SizedBox(height: SFSpacing.xl),

        // ── Title ─────────────────────────────────────────────────────
        Text('SECUREFLOW', style: SFTypography.h1),
        const SizedBox(height: 4),
        Text(
          session.profile?.authMethodLabel != null
              ? '${session.profile!.authMethodLabel} · Hardware-tethered'
              : 'Zero-knowledge enclave',
          style: SFTypography.terminal.copyWith(fontSize: 11),
        ),

        const SizedBox(height: SFSpacing.xl),
        _Divider(),

        // ── Stats ─────────────────────────────────────────────────────
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
              child: _StatTile(
                label: 'DOCUMENTS',
                value: '${docs.length}',
                icon: Icons.folder_outlined,
              ),
            ),
          ],
        ),

        const SizedBox(height: SFSpacing.lg),
        _Divider(),
        const SizedBox(height: SFSpacing.xl),

        // ── Authentication ────────────────────────────────────────────
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

        // ── Cloud Vault (live data) ───────────────────────────────────
        const _SectionHeader('CLOUD VAULT'),
        const SizedBox(height: SFSpacing.md),
        _CloudStatusCard(
          count: cloudCount,
          isLoading: cloudLoading,
          hasError: cloudError,
        ),

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
  final int count;
  final bool isLoading;
  final bool hasError;

  const _CloudStatusCard({
    required this.count,
    required this.isLoading,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;

    if (isLoading) {
      statusText = 'Connecting...';
      statusColor = SFColors.textFaint;
    } else if (hasError) {
      statusText = 'Offline — check credentials in Settings';
      statusColor = SFColors.textFaint;
    } else if (count == 0) {
      statusText = 'No encrypted files in S3';
      statusColor = SFColors.textFaint;
    } else {
      statusText = '$count encrypted file${count == 1 ? '' : 's'} in S3';
      statusColor = SFColors.success;
    }

    return Container(
      padding: const EdgeInsets.all(SFSpacing.md),
      decoration: BoxDecoration(
        color: SFColors.bgCard,
        borderRadius: BorderRadius.circular(SFRadius.card),
        border: Border.all(color: SFColors.borderSoft),
      ),
      child: Row(
        children: [
          Icon(
            hasError ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            size: 20,
            color: hasError ? SFColors.textFaint : SFColors.textMuted,
          ),
          const SizedBox(width: SFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('S3 ENCRYPTED VAULT',
                    style: SFTypography.body.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(statusText,
                    style: SFTypography.bodyMuted
                        .copyWith(fontSize: 11, color: statusColor)),
              ],
            ),
          ),
          const SFBadge('AES-256'),
        ],
      ),
    );
  }
}
