/// Settings Screen — segmented bento lists with danger zone (§2)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../services/vault_provider.dart';
import '../widgets/bento_card.dart';
import '../widgets/tactical_label.dart';
import '../widgets/panic_button.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _autoLockEnabled = true;
  bool _clipboardGuardEnabled = true;
  bool _ramModeOnly = true;

  void _onLockVault() {
    ref.read(sessionProvider.notifier).lock();
  }

  void _onVaultDestruction() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => AlertDialog(
        backgroundColor: SFColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFRadius.card),
          side: const BorderSide(color: SFColors.borderDanger),
        ),
        title: Text(SFCopy.vaultDestruction,
            style: SFTypography.danger.copyWith(fontSize: 14)),
        content: Text(
          'THIS WILL PERMANENTLY ERASE ALL LOCAL DATA AND REVOKE THIS DEVICE\'S ACCESS. THIS ACTION CANNOT BE UNDONE.',
          style: SFTypography.bodyMuted.copyWith(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: SFTypography.button),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(storageServiceProvider).clearAll();
              ref.read(sessionProvider.notifier).lock();
            },
            child: Text('CONFIRM DESTROY', style: SFTypography.danger),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SFSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TacticalLabel('SYSTEM CONFIGURATION', color: SFColors.textMuted),
              const SizedBox(height: 6),
              Text('SETTINGS', style: SFTypography.h1),
              const SizedBox(height: SFSpacing.xl),

              // ── Session info ─────────────────────────────────────
              BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TacticalLabel('SESSION', color: SFColors.textMuted),
                    const SizedBox(height: SFSpacing.md),
                    _SettingRow(
                      label: 'STATUS',
                      value: session.isUnlocked ? 'ACTIVE' : 'LOCKED',
                      valueColor: session.isUnlocked
                          ? SFColors.success : SFColors.textFaint,
                    ),
                    _SettingRow(
                      label: 'AUTH METHOD',
                      value: session.profile?.authMethodLabel ?? '—',
                    ),
                    _SettingRow(
                      label: 'SESSION TIME',
                      value: session.profile?.sessionDuration ?? '—',
                    ),
                    const SizedBox(height: SFSpacing.md),
                    if (session.isUnlocked)
                      OutlinedButton(
                        onPressed: _onLockVault,
                        child: Text(SFCopy.logout,
                            style: SFTypography.button.copyWith(
                                color: SFColors.textMuted)),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: SFSpacing.base),

              // ── Security toggles ──────────────────────────────────
              BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TacticalLabel('SECURITY POLICY', color: SFColors.textMuted),
                    const SizedBox(height: SFSpacing.md),
                    _ToggleRow(
                      label: 'AUTO-LOCK ON BACKGROUND',
                      value: _autoLockEnabled,
                      onChanged: (v) => setState(() => _autoLockEnabled = v),
                    ),
                    const Divider(height: 1, color: SFColors.borderSoft),
                    _ToggleRow(
                      label: 'CLIPBOARD GUARD (5S CLEAR)',
                      value: _clipboardGuardEnabled,
                      onChanged: (v) => setState(() => _clipboardGuardEnabled = v),
                    ),
                    const Divider(height: 1, color: SFColors.borderSoft),
                    _ToggleRow(
                      label: 'RAM-ONLY MODE',
                      value: _ramModeOnly,
                      onChanged: (v) => setState(() => _ramModeOnly = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SFSpacing.base),

              // ── About ─────────────────────────────────────────────
              const BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TacticalLabel('ABOUT', color: SFColors.textMuted),
                    SizedBox(height: SFSpacing.md),
                    _SettingRow(label: 'VERSION', value: '1.0.0'),
                    _SettingRow(label: 'ENCRYPTION', value: 'AES-256-GCM'),
                    _SettingRow(label: 'KEY DERIVE', value: 'HKDF-SHA256'),
                    _SettingRow(label: 'PLATFORM', value: 'ANDROID'),
                  ],
                ),
              ),

              const SizedBox(height: SFSpacing.xl),

              // ── Danger zone ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(SFSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: SFColors.danger.withAlpha(80)),
                  borderRadius: BorderRadius.circular(SFRadius.card),
                  color: SFColors.dangerMuted,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(children: [
                      Icon(Icons.warning_amber_outlined, size: 14,
                          color: SFColors.danger),
                      SizedBox(width: 6),
                      TacticalLabel('DANGER ZONE', color: SFColors.danger),
                    ]),
                    const SizedBox(height: SFSpacing.md),
                    PanicButton(
                      label: SFCopy.emergencyLock,
                      icon: Icons.lock_outline,
                      onPressed: _onLockVault,
                    ),
                    const SizedBox(height: SFSpacing.sm),
                    PanicButton(
                      label: SFCopy.vaultDestruction,
                      icon: Icons.delete_forever_outlined,
                      onPressed: _onVaultDestruction,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SettingRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: SFTypography.metadata.copyWith(fontSize: 10)),
        ),
        Text(value,
            style: SFTypography.terminal.copyWith(
                fontSize: 10,
                color: valueColor ?? SFColors.textMuted)),
      ]),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text(label, style: SFTypography.metadata.copyWith(fontSize: 10)),
        ),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}
