/// Authenticator Screen — horizontal TOTP carousel + add account (§2)
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

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SFColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SFRadius.bento)),
        side: BorderSide(color: SFColors.borderSoft),
      ),
      builder: (_) => _AddTotpSheet(
        onAdd: (key) => ref.read(totpProvider.notifier).add(key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totps = ref.watch(totpProvider);

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      floatingActionButton: GestureDetector(
        onTap: _showAddSheet,
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(SFSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TacticalLabel('IDENTITY TOKENS', color: SFColors.textMuted),
                  const SizedBox(height: 6),
                  Text('AUTHENTICATOR', style: SFTypography.h1),
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
                        onTap: _showAddSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: SFColors.borderMedium),
                            borderRadius: BorderRadius.circular(SFRadius.small),
                          ),
                          child: const TacticalLabel('TAP + TO ADD FIRST TOKEN',
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

  const _TotpCard({
    super.key,
    required this.totpKey,
    required this.remaining,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final code = TotpService.generateCode(totpKey.secret, period: totpKey.period);
    final progress = TotpService.ringProgress(period: totpKey.period);
    final formatted = TotpService.formatCode(code);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SFSpacing.base),
      child: Container(
        decoration: BoxDecoration(
          color: SFColors.bgCard,
          borderRadius: BorderRadius.circular(SFRadius.bento),
          border: Border.all(color: SFColors.borderSoft),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SFSpacing.base),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: TacticalLabel(totpKey.displayName.toUpperCase(),
                        color: SFColors.textMuted),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => _ConfirmDeleteDialog(name: totpKey.displayName),
                      );
                      if (ok == true) onDelete();
                    },
                    child: const Icon(Icons.delete_outline, size: 14,
                        color: SFColors.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(totpKey.metaLine, style: SFTypography.bodyMuted.copyWith(fontSize: 11)),
            const SizedBox(height: SFSpacing.xl),
            TotpRing(
              progress: progress,
              size: 160,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: SFColors.bgCard,
                          duration: const Duration(seconds: 5),
                          content: Text(SFCopy.copying, style: SFTypography.metadata),
                        ),
                      );
                    },
                    child: Text(formatted, style: SFTypography.totpCode),
                  ),
                ],
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
        borderRadius: BorderRadius.circular(SFRadius.bento),
        side: const BorderSide(color: SFColors.borderSoft),
      ),
      title: Text('REMOVE TOKEN', style: SFTypography.body),
      content: Text('Remove "${name.toUpperCase()}" from your vault?',
          style: SFTypography.bodyMuted),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('CANCEL', style: SFTypography.metadata),
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

// ─── Add TOTP bottom sheet ───────────────────────────────────────────────────

class _AddTotpSheet extends StatefulWidget {
  final void Function(TotpKey) onAdd;
  const _AddTotpSheet({required this.onAdd});

  @override
  State<_AddTotpSheet> createState() => _AddTotpSheetState();
}

class _AddTotpSheetState extends State<_AddTotpSheet> {
  bool _scanMode = false;
  bool _scanning = false;
  final MobileScannerController _scanCtrl = MobileScannerController();

  final _issuerCtrl  = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _secretCtrl  = TextEditingController();
  final _periodCtrl  = TextEditingController(text: '30');
  final _formKey = GlobalKey<FormState>();

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

    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'otpauth' && uri.host == 'totp') {
      final labelRaw = Uri.decodeComponent(uri.path.replaceFirst('/', ''));
      final secret = uri.queryParameters['secret'] ?? '';
      final issuer = uri.queryParameters['issuer'] ?? labelRaw.split(':').first;
      final period = int.tryParse(uri.queryParameters['period'] ?? '30') ?? 30;
      final account = labelRaw.contains(':') ? labelRaw.split(':').last : labelRaw;

      if (secret.isNotEmpty) {
        final key = TotpKey(
          id: _genId(),
          label: issuer,
          issuer: issuer,
          account: account,
          secret: secret,
          period: period,
        );
        widget.onAdd(key);
        Navigator.pop(context);
        return;
      }
    }
    setState(() => _scanning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('INVALID QR — NOT A TOTP CODE')),
    );
  }

  void _addManual() {
    if (!_formKey.currentState!.validate()) return;
    final key = TotpKey(
      id: _genId(),
      label: _issuerCtrl.text.trim(),
      issuer: _issuerCtrl.text.trim(),
      account: _accountCtrl.text.trim(),
      secret: _secretCtrl.text.trim().replaceAll(' ', '').toUpperCase(),
      period: int.tryParse(_periodCtrl.text.trim()) ?? 30,
    );
    widget.onAdd(key);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
                  const TacticalLabel('ADD TOTP ACCOUNT', color: SFColors.textMuted),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 18, color: SFColors.textFaint),
                  ),
                ],
              ),
              const SizedBox(height: SFSpacing.xl),

              // Mode toggle
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

              if (_scanMode) ...[
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
                    'POINT CAMERA AT TOTP QR CODE',
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
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: SFSpacing.md),
                    _SfField(
                      ctrl: _accountCtrl,
                      label: 'ACCOUNT NAME (e.g. user@email.com)',
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: SFSpacing.md),
                    _SfField(
                      ctrl: _secretCtrl,
                      label: 'SECRET KEY (Base32)',
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (v.trim().replaceAll(' ', '').length < 8) return 'Too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: SFSpacing.md),
                    _SfField(
                      ctrl: _periodCtrl,
                      label: 'PERIOD IN SECONDS (default 30)',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n < 1) ? 'Must be ≥ 1' : null;
                      },
                    ),
                    const SizedBox(height: SFSpacing.xl),
                    ElevatedButton(
                      onPressed: _addManual,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SFColors.textMain,
                        foregroundColor: SFColors.bgPrimary,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SFRadius.small),
                        ),
                      ),
                      child: Text('ADD TO VAULT', style: SFTypography.button),
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

// Minor typo guard - alias kept for any callers
class TactualLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const TactualLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: color ?? SFColors.textMuted,
      ),
    );
  }
}
