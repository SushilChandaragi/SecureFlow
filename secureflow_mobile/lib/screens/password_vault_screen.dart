/// Password Vault Screen — hold-to-reveal credentials + add/delete (§2)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/credential.dart';
import '../services/vault_provider.dart';
import '../widgets/bento_card.dart';
import '../widgets/tactical_label.dart';

class PasswordVaultScreen extends ConsumerStatefulWidget {
  const PasswordVaultScreen({super.key});

  @override
  ConsumerState<PasswordVaultScreen> createState() => _PasswordVaultScreenState();
}

class _PasswordVaultScreenState extends ConsumerState<PasswordVaultScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
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
      builder: (_) => _AddCredentialSheet(
        onAdd: (cred) => ref.read(credentialProvider.notifier).add(cred),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creds = ref.watch(credentialProvider);
    final filtered = creds.where((c) =>
      c.website.toLowerCase().contains(_query.toLowerCase()) ||
      c.username.toLowerCase().contains(_query.toLowerCase())
    ).toList();

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
                  const TacticalLabel('CREDENTIAL ARCHIVE', color: SFColors.textMuted),
                  const SizedBox(height: 6),
                  Text('PASSWORD VAULT', style: SFTypography.h1),
                  const SizedBox(height: SFSpacing.md),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style: SFTypography.body,
                    decoration: const InputDecoration(
                      hintText: 'SEARCH CREDENTIALS...',
                      prefixIcon: Icon(Icons.search, size: 18,
                          color: SFColors.textFaint),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: SFSpacing.md, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.key_outlined, size: 32,
                              color: SFColors.textFaint),
                          const SizedBox(height: SFSpacing.sm),
                          const TacticalLabel(SFCopy.passwordsEmpty,
                              color: SFColors.textFaint),
                          const SizedBox(height: SFSpacing.xl),
                          GestureDetector(
                            onTap: _showAddSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: SFColors.borderMedium),
                                borderRadius: BorderRadius.circular(SFRadius.small),
                              ),
                              child: const TacticalLabel('TAP + TO ADD CREDENTIAL',
                                  color: SFColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          SFSpacing.base, 0, SFSpacing.base, 100),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: SFSpacing.base),
                      itemBuilder: (_, i) => Dismissible(
                        key: ValueKey(filtered[i].storeKey),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: SFColors.dangerMuted,
                            borderRadius: BorderRadius.circular(SFRadius.bento),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: SFColors.danger, size: 20),
                        ),
                        confirmDismiss: (_) => showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: SFColors.bgCard,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(SFRadius.bento),
                              side: const BorderSide(color: SFColors.borderSoft),
                            ),
                            title: Text('DELETE CREDENTIAL', style: SFTypography.body),
                            content: Text(
                              'Remove "${filtered[i].website}" from vault? This cannot be undone.',
                              style: SFTypography.bodyMuted,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text('CANCEL', style: SFTypography.metadata),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text('DELETE',
                                    style: SFTypography.metadata.copyWith(color: SFColors.danger)),
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (_) =>
                            ref.read(credentialProvider.notifier).remove(filtered[i]),
                        child: _CredentialCard(cred: filtered[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Credential Card ─────────────────────────────────────────────────────────

class _CredentialCard extends StatefulWidget {
  final Credential cred;
  const _CredentialCard({required this.cred});

  @override
  State<_CredentialCard> createState() => _CredentialCardState();
}

class _CredentialCardState extends State<_CredentialCard> {
  bool _revealed = false;
  bool _holding = false;
  Timer? _holdTimer;
  Timer? _clipClearTimer;

  void _onLongPressStart(_) {
    _holdTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _revealed = true);
    });
    setState(() => _holding = true);
  }

  void _onLongPressEnd(_) {
    _holdTimer?.cancel();
    setState(() {
      _holding = false;
      _revealed = false;
    });
  }

  void _copyPassword() {
    Clipboard.setData(ClipboardData(text: widget.cred.password));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SFColors.bgCard,
        duration: const Duration(seconds: 5),
        content: Row(children: [
          const Icon(Icons.content_copy, size: 14, color: SFColors.textMuted),
          const SizedBox(width: 8),
          Text(SFCopy.copying, style: SFTypography.metadata),
        ]),
      ),
    );
    _clipClearTimer?.cancel();
    _clipClearTimer = Timer(const Duration(seconds: 5), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _clipClearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: SFColors.borderSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                widget.cred.website.isNotEmpty
                    ? widget.cred.website[0].toUpperCase()
                    : '?',
                style: SFTypography.body.copyWith(color: SFColors.textMuted),
              ),
            ),
          ),
          const SizedBox(width: SFSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.cred.website, style: SFTypography.body),
                Text(widget.cred.username,
                    style: SFTypography.bodyMuted.copyWith(fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onTap: _copyPassword,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _holding
                    ? SFColors.borderMedium
                    : SFColors.borderSoft,
                borderRadius: BorderRadius.circular(SFRadius.small),
              ),
              child: _revealed
                  ? Text(widget.cred.password,
                      style: SFTypography.terminal.copyWith(fontSize: 11))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.fingerprint, size: 14,
                          color: SFColors.textFaint),
                      const SizedBox(width: 4),
                      Text('HOLD', style: SFTypography.metadata.copyWith(fontSize: 9)),
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Credential Sheet ────────────────────────────────────────────────────

class _AddCredentialSheet extends StatefulWidget {
  final void Function(Credential) onAdd;
  const _AddCredentialSheet({required this.onAdd});

  @override
  State<_AddCredentialSheet> createState() => _AddCredentialSheetState();
}

class _AddCredentialSheetState extends State<_AddCredentialSheet> {
  final _formKey    = GlobalKey<FormState>();
  final _siteCtrl   = TextEditingController();
  final _userCtrl   = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _notesCtrl  = TextEditingController();
  bool _passVisible = false;

  @override
  void dispose() {
    _siteCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final cred = Credential(
      website: _siteCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      notes: _notesCtrl.text.trim(),
    );
    widget.onAdd(cred);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(SFSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    const TacticalLabel('NEW CREDENTIAL', color: SFColors.textMuted),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 18, color: SFColors.textFaint),
                    ),
                  ],
                ),
                const SizedBox(height: SFSpacing.xl),

                // Website/Service
                TextFormField(
                  controller: _siteCtrl,
                  style: SFTypography.body,
                  decoration: const InputDecoration(
                    labelText: 'WEBSITE / SERVICE',
                    prefixIcon: Icon(Icons.language, size: 16, color: SFColors.textFaint),
                    contentPadding: EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 14),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: SFSpacing.md),

                // Username
                TextFormField(
                  controller: _userCtrl,
                  style: SFTypography.body,
                  decoration: const InputDecoration(
                    labelText: 'USERNAME / EMAIL',
                    prefixIcon: Icon(Icons.person_outline, size: 16, color: SFColors.textFaint),
                    contentPadding: EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 14),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: SFSpacing.md),

                // Password
                TextFormField(
                  controller: _passCtrl,
                  obscureText: !_passVisible,
                  style: SFTypography.terminal.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'PASSWORD',
                    prefixIcon: const Icon(Icons.lock_outline, size: 16, color: SFColors.textFaint),
                    suffixIcon: GestureDetector(
                      onTap: () => setState(() => _passVisible = !_passVisible),
                      child: Icon(
                        _passVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 16, color: SFColors.textFaint,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 14),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: SFSpacing.md),

                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  style: SFTypography.body,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'NOTES (optional)',
                    prefixIcon: Icon(Icons.notes, size: 16, color: SFColors.textFaint),
                    contentPadding: EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: 14),
                  ),
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
                  child: Text('SAVE TO VAULT', style: SFTypography.button),
                ),
                const SizedBox(height: SFSpacing.base),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
