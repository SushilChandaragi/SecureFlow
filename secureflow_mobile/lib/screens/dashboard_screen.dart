/// Dashboard Screen — Bento grid main view (§2)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../services/vault_provider.dart';
import '../widgets/bento_card.dart';
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
    // Load vault data after unlock
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
          // Floating nav pill (§9)
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

// ─── Vault Home bento grid ───────────────────────────────────────────────────

class _VaultHome extends ConsumerWidget {
  final String sessionTime;
  const _VaultHome({required this.sessionTime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(vaultFilesProvider);
    final creds = ref.watch(credentialProvider);
    final totps = ref.watch(totpProvider);
    final session = ref.watch(sessionProvider);

    return CustomScrollView(
      slivers: [
        // ── Top bar ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SFSpacing.base, SFSpacing.md,
                SFSpacing.base, 0),
            child: Row(
              children: [
                // Profile glyph
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: SFColors.bgCard,
                    borderRadius: BorderRadius.circular(SFRadius.small),
                    border: Border.all(color: SFColors.borderSoft),
                  ),
                  child: const Center(
                    child: Text('SF',
                        style: TextStyle(color: SFColors.textMuted,
                            fontSize: 12, letterSpacing: 2)),
                  ),
                ),
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
                const SFBadge('RAM-ONLY', color: SFColors.success,
                    background: SFColors.successMuted),
              ],
            ),
          ),
        ),

        // ── Bento grid ──────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(SFSpacing.base, SFSpacing.md,
              SFSpacing.base, 100),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: SFSpacing.base,
            crossAxisSpacing: SFSpacing.base,
            childCount: 5,
            itemBuilder: (context, index) {
              switch (index) {
                // Full-width vault card
                case 0:
                  return _FullWidthVaultCard(files: files);
                // Password vault card
                case 1:
                  return _SmallCard(
                    title: 'PASSWORD VAULT',
                    value: '${creds.length}',
                    subtitle: 'CREDENTIALS',
                    icon: Icons.key_outlined,
                    onTap: () {},
                  );
                // Authenticator card
                case 2:
                  return _SmallCard(
                    title: 'AUTHENTICATOR',
                    value: '${totps.length}',
                    subtitle: 'TOTP KEYS',
                    icon: Icons.shield_outlined,
                    onTap: () {},
                  );
                // Auth method card
                case 3:
                  return _SmallCard(
                    title: 'AUTH METHOD',
                    value: session.profile?.authMethodLabel ?? '—',
                    subtitle: 'HARDWARE KEY',
                    icon: Icons.nfc,
                    onTap: () {},
                  );
                // Analytics card
                case 4:
                  return _AnalyticsPreviewCard();
                default:
                  return const SizedBox.shrink();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _FullWidthVaultCard extends StatelessWidget {
  final AsyncValue<List<dynamic>> files;
  const _FullWidthVaultCard({required this.files});

  @override
  Widget build(BuildContext context) {
    // Span full width via layout
    return LayoutBuilder(builder: (context, constraints) {
      // The staggered grid gives us the column width; we span 2 columns
      return BentoCard(
        elevated: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.lock_outline, size: 16, color: SFColors.textMuted),
              SizedBox(width: 8),
              TacticalLabel('CLOUD VAULT', color: SFColors.textMuted),
              Spacer(),
              SFBadge('AES-256-GCM'),
            ]),
            const SizedBox(height: SFSpacing.md),
            files.when(
              data: (list) => Text('${list.length}',
                  style: SFTypography.dataValue.copyWith(fontSize: 40)),
              loading: () => const SizedBox(height: 40, width: 40,
                  child: CircularProgressIndicator(strokeWidth: 1,
                      color: SFColors.textMuted)),
              error: (_, __) => Text('—', style: SFTypography.dataValue),
            ),
            Text('ENCRYPTED ASSETS', style: SFTypography.metadata),
            const SizedBox(height: SFSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SFColors.textMain.withAlpha(15),
                borderRadius: BorderRadius.circular(SFRadius.small),
                border: Border.all(color: SFColors.borderMedium),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.upload_outlined, size: 14, color: SFColors.textMain),
                const SizedBox(width: 6),
                Text(SFCopy.secureUpload, style: SFTypography.button.copyWith(fontSize: 11)),
              ]),
            ),
          ],
        ),
      );
    });
  }
}

class _SmallCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SmallCard({
    required this.title, required this.value,
    required this.subtitle, required this.icon, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: SFColors.textMuted),
            const SizedBox(width: 6),
            Expanded(child: TacticalLabel(title, color: SFColors.textMuted)),
          ]),
          const SizedBox(height: SFSpacing.md),
          Text(value, style: SFTypography.dataValue),
          const SizedBox(height: 2),
          Text(subtitle, style: SFTypography.metadata),
        ],
      ),
    );
  }
}

class _AnalyticsPreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TacticalLabel(SFCopy.threatIntel, color: SFColors.textMuted),
          const SizedBox(height: SFSpacing.md),
          // Mini monochrome line graph
          SizedBox(
            height: 40,
            child: CustomPaint(painter: _MiniGraphPainter()),
          ),
          const SizedBox(height: SFSpacing.sm),
          Row(children: [
            const Icon(Icons.check_circle_outline, size: 12, color: SFColors.success),
            const SizedBox(width: 4),
            Text('NO THREATS DETECTED', style: SFTypography.metadata.copyWith(fontSize: 9)),
          ]),
        ],
      ),
    );
  }
}

class _MiniGraphPainter extends CustomPainter {
  static const _points = [0.5, 0.4, 0.6, 0.3, 0.5, 0.4, 0.35, 0.45, 0.3];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SFColors.textFaint
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < _points.length; i++) {
      final x = i / (_points.length - 1) * size.width;
      final y = _points[i] * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
