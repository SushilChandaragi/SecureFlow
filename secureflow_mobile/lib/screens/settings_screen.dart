/// Settings Screen — persistent toggles, AWS config, NFC key management (§2)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../services/vault_provider.dart';
import '../widgets/tactical_label.dart';
import '../widgets/panic_button.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ─── Settings state ───────────────────────────────────────────────────────────

class _AppSettings {
  final bool autoLock;
  final bool clipboardGuard;
  final bool ramMode;

  const _AppSettings({
    this.autoLock    = true,
    this.clipboardGuard = true,
    this.ramMode     = true,
  });

  _AppSettings copyWith({bool? autoLock, bool? clipboardGuard, bool? ramMode}) =>
      _AppSettings(
        autoLock:       autoLock       ?? this.autoLock,
        clipboardGuard: clipboardGuard ?? this.clipboardGuard,
        ramMode:        ramMode        ?? this.ramMode,
      );

  Map<String, dynamic> toMap() => {
    'autoLock':       autoLock,
    'clipboardGuard': clipboardGuard,
    'ramMode':        ramMode,
  };

  factory _AppSettings.fromMap(Map<String, dynamic> m) => _AppSettings(
    autoLock:       m['autoLock']       as bool? ?? true,
    clipboardGuard: m['clipboardGuard'] as bool? ?? true,
    ramMode:        m['ramMode']        as bool? ?? true,
  );
}

// ─── Main screen ─────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _AppSettings _settings = const _AppSettings();
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = ref.read(storageServiceProvider);
    final map = await storage.loadSettings();
    if (mounted) {
      setState(() {
        _settings = map.isNotEmpty ? _AppSettings.fromMap(map) : const _AppSettings();
        _loaded = true;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    final storage = ref.read(storageServiceProvider);
    await storage.saveSettings(_settings.toMap());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SFColors.bgCard,
        duration: const Duration(seconds: 2),
        content: Row(children: [
          const Icon(Icons.check_circle_outline, size: 14, color: SFColors.success),
          const SizedBox(width: 8),
          Text('SETTINGS SAVED', style: SFTypography.metadata.copyWith(color: SFColors.success)),
        ]),
      ),
    );
  }

  void _onLockVault() => ref.read(sessionProvider.notifier).lock();

  void _onClearCorruptData() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => AlertDialog(
        backgroundColor: SFColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFRadius.card),
          side: const BorderSide(color: SFColors.borderDanger),
        ),
        title: Text('CLEAR CORRUPT DATA',
            style: SFTypography.danger.copyWith(fontSize: 14)),
        content: Text(
          'Wipes all encrypted rows (credentials, TOTP, local docs) written before the v1.0.1 crypto fix. Use this ONCE if data shows as corrupt after the update. Cloud S3 files are NOT deleted.',
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
              final db = ref.read(databaseServiceProvider);
              await db.clearAllRows();
              ref.read(credentialProvider.notifier).load();
              ref.read(totpProvider.notifier).load();
              ref.read(documentProvider.notifier).load();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: SFColors.bgCard,
                  content: Text('CORRUPT ROWS CLEARED — DB RESET',
                      style: SFTypography.metadata.copyWith(color: SFColors.success)),
                ),
              );
            },
            child: Text('CONFIRM CLEAR', style: SFTypography.danger),
          ),
        ],
      ),
    );
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
          'THIS WILL PERMANENTLY ERASE ALL LOCAL DATA AND REVOKE THIS DEVICE\'S ACCESS.',
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

  void _showAwsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SFColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SFRadius.bento)),
        side: BorderSide(color: SFColors.borderSoft),
      ),
      builder: (_) => _AwsConfigSheet(storage: ref.read(storageServiceProvider)),
    );
  }

  void _showNfcResetSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SFColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SFRadius.bento)),
        side: BorderSide(color: SFColors.borderSoft),
      ),
      builder: (_) => _NfcKeySheet(storage: ref.read(storageServiceProvider)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              SFSpacing.base, SFSpacing.md, SFSpacing.base, 110),
          children: [
            // ── Header ───────────────────────────────────────────────
            const TacticalLabel('SYSTEM CONFIGURATION', color: SFColors.textMuted),
            const SizedBox(height: 6),
            Text('SETTINGS', style: SFTypography.h1),

            const SizedBox(height: SFSpacing.xl),
            _divider(),

            // ── Session ───────────────────────────────────────────────
            const SizedBox(height: SFSpacing.lg),
            const TacticalLabel('SESSION', color: SFColors.textFaint),
            const SizedBox(height: SFSpacing.md),
            _InfoRow('STATUS',
              session.isUnlocked ? 'ACTIVE' : 'LOCKED',
              valueColor: session.isUnlocked ? SFColors.success : SFColors.textFaint),
            _InfoRow('AUTH METHOD', session.profile?.authMethodLabel ?? '—'),
            _InfoRow('SESSION TIME', session.profile?.sessionDuration ?? '—'),
            const SizedBox(height: SFSpacing.md),
            if (session.isUnlocked)
              _OutlineButton(
                label: SFCopy.logout,
                icon: Icons.logout,
                onTap: _onLockVault,
              ),

            const SizedBox(height: SFSpacing.xl),
            _divider(),

            // ── Security toggles ──────────────────────────────────────
            const SizedBox(height: SFSpacing.lg),
            const TacticalLabel('SECURITY POLICY', color: SFColors.textFaint),
            const SizedBox(height: SFSpacing.md),
            if (!_loaded)
              const Center(
                child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 1, color: SFColors.textFaint)),
              )
            else ...[
              _ToggleRow(
                label: 'AUTO-LOCK ON BACKGROUND',
                sublabel: 'Lock vault when app moves to background',
                value: _settings.autoLock,
                onChanged: (v) => setState(() => _settings = _settings.copyWith(autoLock: v)),
              ),
              _ToggleRow(
                label: 'CLIPBOARD GUARD',
                sublabel: 'Clear clipboard 5s after copying',
                value: _settings.clipboardGuard,
                onChanged: (v) => setState(() => _settings = _settings.copyWith(clipboardGuard: v)),
              ),
              _ToggleRow(
                label: 'RAM-ONLY MODE',
                sublabel: 'Never write secrets to disk cache',
                value: _settings.ramMode,
                onChanged: (v) => setState(() => _settings = _settings.copyWith(ramMode: v)),
              ),
              const SizedBox(height: SFSpacing.md),
              _FilledButton(
                label: _saving ? 'SAVING...' : 'SAVE SETTINGS',
                icon: Icons.save_outlined,
                onTap: _saving ? null : _saveSettings,
              ),
            ],

            const SizedBox(height: SFSpacing.xl),
            _divider(),

            // ── Cloud config ──────────────────────────────────────────
            const SizedBox(height: SFSpacing.lg),
            const TacticalLabel('CLOUD VAULT', color: SFColors.textFaint),
            const SizedBox(height: SFSpacing.md),
            const _InfoRow('PROVIDER', 'AWS S3'),
            const _InfoRow('ENCRYPTION', 'AES-256-GCM CLIENT-SIDE'),
            const SizedBox(height: SFSpacing.md),
            _OutlineButton(
              label: 'CONFIGURE AWS CREDENTIALS',
              icon: Icons.cloud_outlined,
              onTap: _showAwsSheet,
            ),

            const SizedBox(height: SFSpacing.xl),
            _divider(),

            // ── NFC key ───────────────────────────────────────────────
            const SizedBox(height: SFSpacing.lg),
            const TacticalLabel('NFC HARDWARE KEY', color: SFColors.textFaint),
            const SizedBox(height: SFSpacing.md),
            const _InfoRow('TAG TYPE', 'MIFARE CLASSIC 1K / NDEF TEXT'),
            const _InfoRow('FORMAT', 'SECUREFLOW-NFC-KEY-V1-[8CHARS]'),
            const SizedBox(height: SFSpacing.md),
            _OutlineButton(
              label: 'VIEW / RESET NFC KEY',
              icon: Icons.nfc_outlined,
              onTap: _showNfcResetSheet,
            ),

            const SizedBox(height: SFSpacing.xl),
            _divider(),

            // ── About ─────────────────────────────────────────────────
            const SizedBox(height: SFSpacing.lg),
            const TacticalLabel('ABOUT', color: SFColors.textFaint),
            const SizedBox(height: SFSpacing.md),
            const _InfoRow('VERSION', '1.0.0'),
            const _InfoRow('ENCRYPTION', 'AES-256-GCM'),
            const _InfoRow('KEY DERIVE', 'HKDF-SHA256'),
            const _InfoRow('PLATFORM', 'ANDROID'),

            const SizedBox(height: SFSpacing.xl),
            _divider(),

            // ── Danger zone ───────────────────────────────────────────
            const SizedBox(height: SFSpacing.lg),
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
                    Icon(Icons.warning_amber_outlined, size: 14, color: SFColors.danger),
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
                    label: 'CLEAR CORRUPT DB ROWS',
                    icon: Icons.cleaning_services_outlined,
                    onPressed: _onClearCorruptData,
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
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(height: 1, color: SFColors.borderSoft);
}

// ─── Reusable row widgets ─────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: SFTypography.metadata.copyWith(fontSize: 10)),
        ),
        Flexible(
          child: Text(value,
            style: SFTypography.terminal.copyWith(
                fontSize: 10, color: valueColor ?? SFColors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: SFTypography.metadata.copyWith(fontSize: 10)),
              Text(sublabel,
                  style: SFTypography.bodyMuted.copyWith(fontSize: 10)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: SFColors.textMain,
          inactiveTrackColor: SFColors.borderSoft,
        ),
      ]),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _OutlineButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: SFColors.borderMedium),
          borderRadius: BorderRadius.circular(SFRadius.small),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: SFColors.textMuted),
          const SizedBox(width: SFSpacing.sm),
          Expanded(child: Text(label,
              style: SFTypography.metadata.copyWith(color: SFColors.textMuted))),
          const Icon(Icons.chevron_right, size: 16, color: SFColors.textFaint),
        ]),
      ),
    );
  }
}

class _FilledButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _FilledButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 13),
        decoration: BoxDecoration(
          color: onTap == null ? SFColors.borderSoft : SFColors.textMain,
          borderRadius: BorderRadius.circular(SFRadius.small),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: SFColors.bgPrimary),
          const SizedBox(width: SFSpacing.sm),
          Text(label,
              style: SFTypography.metadata.copyWith(color: SFColors.bgPrimary)),
        ]),
      ),
    );
  }
}

// ─── AWS Config Bottom Sheet ──────────────────────────────────────────────────

class _AwsConfigSheet extends StatefulWidget {
  final dynamic storage;
  const _AwsConfigSheet({required this.storage});

  @override
  State<_AwsConfigSheet> createState() => _AwsConfigSheetState();
}

class _AwsConfigSheetState extends State<_AwsConfigSheet> {
  final _formKey   = GlobalKey<FormState>();
  final _keyCtrl   = TextEditingController();
  final _secCtrl   = TextEditingController();
  final _regCtrl   = TextEditingController();
  final _bktCtrl   = TextEditingController();
  final _sharedSecretCtrl = TextEditingController();
  bool _saving     = false;
  bool _loaded     = false;
  bool _secretObscure = true;
  bool _showQrScanner = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final creds = await widget.storage.loadAwsCredentials();
    final sharedSecret = await widget.storage.loadDesktopSecretString();
    if (mounted) {
      setState(() {
        if (creds != null) {
          _keyCtrl.text = creds['accessKeyId'] ?? '';
          _secCtrl.text = creds['secretAccessKey'] ?? '';
          _regCtrl.text = creds['region'] ?? '';
          _bktCtrl.text = creds['bucketName'] ?? '';
        }
        _sharedSecretCtrl.text = sharedSecret ?? '';
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.storage.saveAwsCredentials(
      accessKeyId:     _keyCtrl.text.trim(),
      secretAccessKey: _secCtrl.text.trim(),
      region:          _regCtrl.text.trim(),
      bucketName:      _bktCtrl.text.trim(),
    );
    // Save the desktop shared secret if the user entered one.
    final secret = _sharedSecretCtrl.text; // preserve exact content incl \r\n if pasted
    if (secret.isNotEmpty) {
      await widget.storage.saveDesktopSecret(secret);
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SFColors.bgCard,
        duration: const Duration(seconds: 2),
        content: Text('CREDENTIALS SAVED', style: SFTypography.metadata.copyWith(color: SFColors.success)),
      ),
    );
  }

  @override
  void dispose() {
    _keyCtrl.dispose(); _secCtrl.dispose();
    _regCtrl.dispose(); _bktCtrl.dispose();
    _sharedSecretCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(SFSpacing.xl),
          child: !_loaded
            ? const Center(child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 1, color: SFColors.textFaint)))
            : Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const TacticalLabel('AWS S3 CREDENTIALS', color: SFColors.textMuted),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 18, color: SFColors.textFaint),
                    ),
                  ]),
                  const SizedBox(height: SFSpacing.lg),
                  _field(_keyCtrl, 'ACCESS KEY ID', Icons.vpn_key_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: SFSpacing.md),
                  _field(_secCtrl, 'SECRET ACCESS KEY', Icons.lock_outline,
                      obscure: true,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: SFSpacing.md),
                  _field(_regCtrl, 'REGION (e.g. us-east-1)', Icons.public_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: SFSpacing.md),
                  _field(_bktCtrl, 'S3 BUCKET NAME', Icons.storage_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: SFSpacing.lg),
                  // Divider between AWS creds and vault key
                  const Divider(color: SFColors.borderSoft, height: 1),
                  const SizedBox(height: SFSpacing.lg),
                  Row(children: [
                    const TacticalLabel('DESKTOP VAULT SECRET', color: SFColors.textMuted),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _showQrScanner = !_showQrScanner),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: SFColors.bgPrimary,
                          borderRadius: BorderRadius.circular(SFRadius.small),
                          border: Border.all(color: SFColors.borderSoft),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _showQrScanner ? Icons.keyboard_outlined : Icons.qr_code_scanner_outlined,
                              size: 12,
                              color: SFColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showQrScanner ? 'MANUAL' : 'SCAN QR',
                              style: SFTypography.metadata.copyWith(fontSize: 10, color: SFColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    'Paste the contents of mock_hardware_secret.txt from your desktop, or click SCAN QR to scan the pairing QR code.',
                    style: SFTypography.bodyMuted.copyWith(fontSize: 10),
                  ),
                  const SizedBox(height: SFSpacing.md),
                  if (_showQrScanner) ...[
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(SFRadius.small),
                        border: Border.all(color: SFColors.borderSoft),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: MobileScanner(
                        onDetect: (capture) {
                          final raw = capture.barcodes.firstOrNull?.rawValue;
                          if (raw != null) {
                            final trimmed = raw.trim();
                            setState(() {
                              _sharedSecretCtrl.text = trimmed;
                              _showQrScanner = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🟢 DESKTOP SECRET CAPTURED SUCCESSFULLY!'),
                                backgroundColor: Color(0xFF10B981),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: SFSpacing.md),
                  ],
                  TextFormField(
                    controller: _sharedSecretCtrl,
                    obscureText: _secretObscure,
                    style: SFTypography.terminal.copyWith(fontSize: 12, color: SFColors.textMain),
                    decoration: InputDecoration(
                      labelText: 'VAULT SHARED SECRET',
                      labelStyle: SFTypography.metadata.copyWith(color: SFColors.textFaint),
                      prefixIcon: const Icon(Icons.key_outlined, size: 16, color: SFColors.textFaint),
                      suffixIcon: GestureDetector(
                        onTap: () => setState(() => _secretObscure = !_secretObscure),
                        child: Icon(
                          _secretObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 16, color: SFColors.textFaint,
                        ),
                      ),
                      hintText: 'SecureFlow-Mock-Secret-Change-Me...',
                      hintStyle: SFTypography.bodyMuted.copyWith(fontSize: 10),
                      filled: true, fillColor: SFColors.bgPrimary,
                      contentPadding: const EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SFRadius.small),
                        borderSide: const BorderSide(color: SFColors.borderSoft)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SFRadius.small),
                        borderSide: const BorderSide(color: SFColors.borderSoft)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SFRadius.small),
                        borderSide: const BorderSide(color: SFColors.borderMedium)),
                    ),
                  ),
                  const SizedBox(height: SFSpacing.xl),
                  _FilledButton(
                    label: _saving ? 'SAVING...' : 'SAVE CREDENTIALS',
                    icon: Icons.cloud_done_outlined,
                    onTap: _saving ? null : _save,
                  ),
                  const SizedBox(height: SFSpacing.base),
                ],
              ),
            ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      validator: validator,
      style: SFTypography.terminal.copyWith(fontSize: 12, color: SFColors.textMain),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: SFTypography.metadata.copyWith(color: SFColors.textFaint),
        prefixIcon: Icon(icon, size: 16, color: SFColors.textFaint),
        filled: true, fillColor: SFColors.bgPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.borderSoft)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.borderSoft)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.borderMedium)),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.danger)),
      ),
    );
  }
}

// ─── NFC Key Sheet ────────────────────────────────────────────────────────────

class _NfcKeySheet extends StatefulWidget {
  final dynamic storage;
  const _NfcKeySheet({required this.storage});

  @override
  State<_NfcKeySheet> createState() => _NfcKeySheetState();
}

class _NfcKeySheetState extends State<_NfcKeySheet> {
  String? _storedKey;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.storage.loadNfcSecretString().then((k) {
      if (mounted) setState(() { _storedKey = k; _loaded = true; });
    });
  }

  Future<void> _resetKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SFColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFRadius.bento),
          side: const BorderSide(color: SFColors.borderDanger),
        ),
        title: Text('RESET NFC KEY', style: SFTypography.body),
        content: Text(
          'This will unbind the current NFC tag. The next NFC tap will bind to a new tag.',
          style: SFTypography.bodyMuted.copyWith(fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('CANCEL', style: SFTypography.metadata)),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('RESET', style: SFTypography.metadata.copyWith(color: SFColors.danger))),
        ],
      ),
    );
    if (ok == true) {
      await widget.storage.saveNfcSecretString('');
      if (mounted) {
        setState(() => _storedKey = null);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SFColors.bgCard,
            content: Text('NFC KEY CLEARED — TAP NEW TAG TO BIND',
                style: SFTypography.metadata.copyWith(color: SFColors.success)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SFSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const TacticalLabel('NFC KEY MANAGEMENT', color: SFColors.textMuted),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, size: 18, color: SFColors.textFaint),
            ),
          ]),
          const SizedBox(height: SFSpacing.xl),
          if (!_loaded)
            const Center(child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 1, color: SFColors.textFaint)))
          else ...[
            Container(
              padding: const EdgeInsets.all(SFSpacing.md),
              decoration: BoxDecoration(
                color: SFColors.bgPrimary,
                borderRadius: BorderRadius.circular(SFRadius.small),
                border: Border.all(color: SFColors.borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TacticalLabel('BOUND KEY', color: SFColors.textFaint),
                  const SizedBox(height: SFSpacing.sm),
                  Text(
                    (_storedKey != null && _storedKey!.isNotEmpty)
                        ? _storedKey!
                        : 'NOT BOUND — NEXT NFC TAP WILL BIND',
                    style: SFTypography.terminal.copyWith(fontSize: 11,
                        color: (_storedKey != null && _storedKey!.isNotEmpty)
                            ? SFColors.success
                            : SFColors.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SFSpacing.lg),
            const TacticalLabel(
              'HOW TO WRITE YOUR NFC TAG:',
              color: SFColors.textFaint,
            ),
            const SizedBox(height: SFSpacing.sm),
            Text(
              '1. Install "NFC Tools" app\n'
              '2. Write → Add Record → Text\n'
              '3. Enter: SECUREFLOW-NFC-KEY-V1-[8CHARS]\n'
              '4. Tap the + NFC button in login screen\n'
              '5. Present the tag — first tap binds it',
              style: SFTypography.bodyMuted.copyWith(fontSize: 11, height: 1.8),
            ),
            if (_storedKey != null && _storedKey!.isNotEmpty) ...[
              const SizedBox(height: SFSpacing.lg),
              GestureDetector(
                onTap: _resetKey,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: SFColors.danger.withAlpha(120)),
                    borderRadius: BorderRadius.circular(SFRadius.small),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.nfc, size: 14, color: SFColors.danger),
                    const SizedBox(width: 6),
                    Text('RESET & REBIND NFC TAG',
                        style: SFTypography.metadata.copyWith(color: SFColors.danger)),
                  ]),
                ),
              ),
            ],
          ],
          const SizedBox(height: SFSpacing.base),
        ],
      ),
    );
  }
}
