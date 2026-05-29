/// Authenticator Screen — horizontal TOTP carousel + add/edit account (§2)
library;

import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/totp_key.dart';
import '../services/vault_provider.dart';
import '../services/totp_service.dart';
import '../widgets/tactical_label.dart';
import '../widgets/totp_ring.dart';

// Helper: generate a short random ID for new TOTP keys
String _genId() =>
    DateTime.now().millisecondsSinceEpoch.toRadixString(16) +
    Random.secure().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');

// ─── Main Screen ─────────────────────────────────────────────────────────────

class AuthenticatorScreen extends ConsumerStatefulWidget {
  const AuthenticatorScreen({super.key});

  @override
  ConsumerState<AuthenticatorScreen> createState() => _AuthenticatorScreenState();
}

class _AuthenticatorScreenState extends ConsumerState<AuthenticatorScreen> {
  Timer? _codeTimer;
  int _remaining = 30;
  int _pageIndex = 0;
  final _pageCtrl = PageController();

  @override
  void initState() {
    super.initState();
    _remaining = TotpService.remainingSeconds();
    _codeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = TotpService.remainingSeconds());
    });
  }

  @override
  void dispose() {
    _codeTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _showAddSheet([TotpKey? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SFColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SFRadius.bento)),
        side: BorderSide(color: SFColors.borderSoft),
      ),
      builder: (_) => _AddTotpSheet(
        existing: existing,
        onSave: (key) {
          if (existing != null) {
            ref.read(totpProvider.notifier).update(key);
          } else {
            ref.read(totpProvider.notifier).add(key);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totps = ref.watch(totpProvider);

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: GestureDetector(
          onTap: () => _showAddSheet(),
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: SFColors.textMain,
              borderRadius: BorderRadius.circular(SFRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(100),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.add, color: SFColors.bgPrimary, size: 24),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(SFSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MFA CODES', style: SFTypography.h1),
                ],
              ),
            ),

            if (totps.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 36,
                          color: SFColors.textFaint),
                      const SizedBox(height: SFSpacing.sm),
                      const TacticalLabel(SFCopy.totpEmpty, color: SFColors.textFaint),
                      const SizedBox(height: SFSpacing.xl),
                      GestureDetector(
                        onTap: () => _showAddSheet(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: SFColors.borderMedium),
                            borderRadius: BorderRadius.circular(SFRadius.small),
                          ),
                            child: const TacticalLabel('TAP + TO ADD FIRST CODE',
                              color: SFColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 340,
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _pageIndex = i),
                  itemCount: totps.length,
                  itemBuilder: (_, i) => _TotpCard(
                    key: ValueKey(totps[i].id),
                    totpKey: totps[i],
                    remaining: _remaining,
                    onDelete: () => ref.read(totpProvider.notifier).remove(totps[i].id),
                    onEdit: () => _showAddSheet(totps[i]),
                  ),
                ),
              ),
              const SizedBox(height: SFSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totps.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _pageIndex ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _pageIndex
                        ? SFColors.textMain : SFColors.borderSoft,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── TOTP card ───────────────────────────────────────────────────────────────

class _TotpCard extends StatelessWidget {
  final TotpKey totpKey;
  final int remaining;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TotpCard({
    super.key,
    required this.totpKey,
    required this.remaining,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isValid = TotpService.isSecretValid(totpKey.secret);
    final code     = TotpService.generateCode(totpKey.secret, period: totpKey.period);
    final progress = TotpService.ringProgress(period: totpKey.period);
    final formatted = TotpService.formatCode(code);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SFSpacing.base),
      child: Container(
        decoration: BoxDecoration(
          color: SFColors.bgCard,
          borderRadius: BorderRadius.circular(SFRadius.bento),
          border: Border.all(
            color: isValid ? SFColors.borderSoft : SFColors.borderDanger,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Header row (label + edit + delete) ──────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SFSpacing.base),
              child: Row(
                children: [
                  Expanded(
                    child: TacticalLabel(
                      totpKey.displayName.toUpperCase(),
                      color: SFColors.textMuted,
                    ),
                  ),
                  // Error badge for invalid secret
                  if (!isValid) ...[
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: SFColors.danger),
                    const SizedBox(width: 6),
                  ],
                  // Edit button
                  GestureDetector(
                    onTap: onEdit,
                    child: const Icon(Icons.edit_outlined,
                        size: 14, color: SFColors.textFaint),
                  ),
                  const SizedBox(width: 10),
                  // Delete button
                  GestureDetector(
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => _ConfirmDeleteDialog(name: totpKey.displayName),
                      );
                      if (ok == true) onDelete();
                    },
                    child: const Icon(Icons.delete_outline,
                        size: 14, color: SFColors.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(totpKey.metaLine,
                style: SFTypography.bodyMuted.copyWith(fontSize: 11)),

            // ── Invalid secret warning ────────────────────────────────────
            if (!isValid) ...[
              const SizedBox(height: SFSpacing.sm),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: SFSpacing.base),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SFColors.dangerMuted,
                  borderRadius: BorderRadius.circular(SFRadius.small),
                  border: Border.all(color: SFColors.borderDanger),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 12, color: SFColors.danger),
                    const SizedBox(width: 6),
                    Text('INVALID BASE32 SECRET — TAP ✏ TO FIX',
                        style: SFTypography.metadata.copyWith(
                            color: SFColors.danger, fontSize: 10)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: SFSpacing.xl),

            // ── TOTP ring — code perfectly centred via Stack ──────────────
            TotpRing(
              progress: progress,
              size: 160,
              child: GestureDetector(
                onTap: isValid
                    ? () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: SFColors.bgCard,
                            duration: const Duration(seconds: 5),
                            content: Text(SFCopy.copying,
                                style: SFTypography.metadata),
                          ),
                        );
                      }
                    : null,
                child: Text(
                  formatted,
                  style: isValid
                      ? SFTypography.totpCode
                      : SFTypography.totpCode.copyWith(
                          color: SFColors.danger.withAlpha(180)),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            const SizedBox(height: SFSpacing.md),
            Text(
              '${remaining}S REMAINING',
              style: SFTypography.metadata.copyWith(
                color: remaining < 8 ? SFColors.danger : SFColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Confirm delete dialog ───────────────────────────────────────────────────

class _ConfirmDeleteDialog extends StatelessWidget {
  final String name;
  const _ConfirmDeleteDialog({required this.name});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SFColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SFRadius.card),
        side: const BorderSide(color: SFColors.borderDanger),
      ),
      title: Text('REMOVE CODE', style: SFTypography.cardTitle),
      content: Text(
        'Delete "$name" from vault?\nThis cannot be undone.',
        style: SFTypography.bodyMuted,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('CANCEL',
              style: SFTypography.metadata.copyWith(color: SFColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('REMOVE',
              style: SFTypography.metadata.copyWith(color: SFColors.danger)),
        ),
      ],
    );
  }
}

// ─── Add / Edit TOTP bottom sheet ────────────────────────────────────────────

class _AddTotpSheet extends ConsumerStatefulWidget {
  final TotpKey? existing;
  final void Function(TotpKey) onSave;
  const _AddTotpSheet({this.existing, required this.onSave});

  @override
  ConsumerState<_AddTotpSheet> createState() => _AddTotpSheetState();
}

class _AddTotpSheetState extends ConsumerState<_AddTotpSheet> {
  bool _scanMode = false;
  bool _scanning = false;
  final MobileScannerController _scanCtrl = MobileScannerController();

  late final TextEditingController _issuerCtrl;
  late final TextEditingController _accountCtrl;
  late final TextEditingController _secretCtrl;
  late final TextEditingController _periodCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _issuerCtrl  = TextEditingController(text: e?.issuer  ?? '');
    _accountCtrl = TextEditingController(text: e?.account ?? '');
    _secretCtrl  = TextEditingController(text: e?.secret  ?? '');
    _periodCtrl  = TextEditingController(text: (e?.period ?? 30).toString());
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _issuerCtrl.dispose();
    _accountCtrl.dispose();
    _secretCtrl.dispose();
    _periodCtrl.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_scanning) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() => _scanning = true);

    final trimmed = raw.trim();
    if (trimmed.startsWith('SecureFlow-') || trimmed.length >= 32) {
      _pairMobileCompanion(trimmed);
      return;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'otpauth' && uri.host == 'totp') {
      final labelRaw = Uri.decodeComponent(uri.path.replaceFirst('/', ''));
      final secret   = uri.queryParameters['secret'] ?? '';
      final issuer   = uri.queryParameters['issuer'] ?? labelRaw.split(':').first;
      final period   = int.tryParse(uri.queryParameters['period'] ?? '30') ?? 30;
      final account  = labelRaw.contains(':') ? labelRaw.split(':').last : labelRaw;

      if (secret.isNotEmpty) {
        final key = TotpKey(
          id:      widget.existing?.id ?? _genId(),
          label:   issuer,
          issuer:  issuer,
          account: account,
          secret:  secret,
          period:  period,
        );
        widget.onSave(key);
        Navigator.pop(context);
        return;
      }
    }
    setState(() => _scanning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('INVALID QR — NOT AN MFA CODE')),
    );
  }

  Future<void> _pairMobileCompanion(String secret) async {
    try {
      final storage = ref.read(storageServiceProvider);
      await storage.saveDesktopSecret(secret);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🟢 MOBILE COMPANION PAIRED SUCCESSFULLY!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ERROR PAIRING: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      setState(() => _scanning = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final key = TotpKey(
      id:      widget.existing?.id ?? _genId(),
      label:   _issuerCtrl.text.trim(),
      issuer:  _issuerCtrl.text.trim(),
      account: _accountCtrl.text.trim(),
      secret:  _secretCtrl.text.trim().replaceAll(' ', '').toUpperCase(),
      period:  int.tryParse(_periodCtrl.text.trim()) ?? 30,
    );
    widget.onSave(key);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(SFSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TacticalLabel(
                    isEdit ? 'EDIT MFA CODE' : 'ADD MFA CODE',
                    color: SFColors.textMuted,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 18, color: SFColors.textFaint),
                  ),
                ],
              ),
              const SizedBox(height: SFSpacing.xl),

              // Mode toggle (only show for new entries)
              if (!isEdit) ...[
                Row(children: [
                  _ModeBtn(
                    label: 'SCAN QR',
                    icon: Icons.qr_code_scanner,
                    selected: _scanMode,
                    onTap: () => setState(() => _scanMode = true),
                  ),
                  const SizedBox(width: SFSpacing.sm),
                  _ModeBtn(
                    label: 'MANUAL',
                    icon: Icons.keyboard_outlined,
                    selected: !_scanMode,
                    onTap: () => setState(() => _scanMode = false),
                  ),
                ]),
                const SizedBox(height: SFSpacing.xl),
              ],

              if (_scanMode && !isEdit) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(SFRadius.bento),
                  child: SizedBox(
                    height: 260,
                    child: MobileScanner(
                      controller: _scanCtrl,
                      onDetect: _handleBarcode,
                    ),
                  ),
                ),
                const SizedBox(height: SFSpacing.md),
                Center(
                  child: Text(
                    'POINT CAMERA AT MFA QR CODE',
                    style: SFTypography.metadata.copyWith(color: SFColors.textFaint),
                  ),
                ),
              ] else ...[
                Form(
                  key: _formKey,
                  child: Column(children: [
                    _SfField(
                      ctrl: _issuerCtrl,
                      label: 'ISSUER (e.g. GitHub)',
                      validator: (v) => (v == null || v.isEmpty) ? 'REQUIRED' : null,
                    ),
                    const SizedBox(height: SFSpacing.md),
                    _SfField(
                      ctrl: _accountCtrl,
                      label: 'ACCOUNT (e.g. user@email.com)',
                      validator: (v) => (v == null || v.isEmpty) ? 'REQUIRED' : null,
                    ),
                    const SizedBox(height: SFSpacing.md),
                    _SfField(
                      ctrl: _secretCtrl,
                      label: 'SECRET KEY (Base32)',
                      // Use the safe TotpService validator
                      validator: (v) => TotpService.validateBase32(v),
                    ),
                    const SizedBox(height: SFSpacing.md),
                    _SfField(
                      ctrl: _periodCtrl,
                      label: 'PERIOD IN SECONDS (default 30)',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n < 1) ? 'MUST BE ≥ 1' : null;
                      },
                    ),
                    const SizedBox(height: SFSpacing.xl),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SFColors.textMain,
                        foregroundColor: SFColors.bgPrimary,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SFRadius.small),
                        ),
                      ),
                      child: Text(
                        isEdit ? 'UPDATE CODE' : 'ADD TO VAULT',
                        style: SFTypography.button,
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: SFSpacing.base),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mode button ─────────────────────────────────────────────────────────────

class _ModeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? SFColors.textMain : SFColors.bgCard,
            borderRadius: BorderRadius.circular(SFRadius.small),
            border: Border.all(
              color: selected ? SFColors.textMain : SFColors.borderSoft,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14,
                  color: selected ? SFColors.bgPrimary : SFColors.textMuted),
              const SizedBox(width: 6),
              Text(label,
                style: SFTypography.metadata.copyWith(
                  color: selected ? SFColors.bgPrimary : SFColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Text field helper ───────────────────────────────────────────────────────

class _SfField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  const _SfField({
    required this.ctrl,
    required this.label,
    this.validator,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      keyboardType: keyboardType,
      style: SFTypography.body,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: SFTypography.metadata.copyWith(color: SFColors.textFaint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 14),
      ),
    );
  }
}
