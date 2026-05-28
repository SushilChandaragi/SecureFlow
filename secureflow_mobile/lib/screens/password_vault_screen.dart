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
import '../widgets/tactical_label.dart';

class PasswordVaultScreen extends ConsumerStatefulWidget {
  const PasswordVaultScreen({super.key});

  @override
  ConsumerState<PasswordVaultScreen> createState() =>
      _PasswordVaultScreenState();
}

class _PasswordVaultScreenState extends ConsumerState<PasswordVaultScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Hydrate from local storage every time this screen is shown
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(credentialProvider.notifier).load();
      if (mounted) setState(() => _loading = false);
    });
  }

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
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SFRadius.bento)),
        side: BorderSide(color: SFColors.borderSoft),
      ),
      builder: (_) => _AddCredentialSheet(
        onAdd: (cred) => ref.read(credentialProvider.notifier).add(cred),
      ),
    );
  }

  void _showEditSheet(Credential existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SFColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SFRadius.bento)),
        side: BorderSide(color: SFColors.borderSoft),
      ),
      builder: (_) => _AddCredentialSheet(
        existing: existing,
        onAdd: (updated) =>
            ref.read(credentialProvider.notifier).update(existing, updated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creds = ref.watch(credentialProvider);
    final filtered = creds
        .where((c) =>
            c.website.toLowerCase().contains(_query.toLowerCase()) ||
            c.username.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,

      // ── FAB ──────────────────────────────────────────────────────────
      floatingActionButton: GestureDetector(
        onTap: _showAddSheet,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: SFColors.textMain,
            borderRadius: BorderRadius.circular(SFRadius.pill),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withAlpha(100),
                  blurRadius: 16,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.add, color: SFColors.bgPrimary, size: 24),
        ),
      ),

      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SFSpacing.base, SFSpacing.md, SFSpacing.base, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TacticalLabel('CREDENTIAL ARCHIVE',
                      color: SFColors.textMuted),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                          child: Text('PASSWORD VAULT', style: SFTypography.h1)),
                      if (!_loading)
                        TacticalLabel('${creds.length} STORED',
                            color: SFColors.textFaint),
                    ],
                  ),
                ],
              ),
            ),

            // ── Search bar ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SFSpacing.base, SFSpacing.md, SFSpacing.base, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: SFTypography.body,
                decoration: InputDecoration(
                  hintText: 'SEARCH CREDENTIALS...',
                  hintStyle:
                      SFTypography.body.copyWith(color: SFColors.textFaint),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: SFColors.textFaint),
                  filled: true,
                  fillColor: SFColors.bgCard,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: SFSpacing.md, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SFRadius.small),
                    borderSide: const BorderSide(color: SFColors.borderSoft),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SFRadius.small),
                    borderSide: const BorderSide(color: SFColors.borderSoft),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SFRadius.small),
                    borderSide:
                        const BorderSide(color: SFColors.borderMedium),
                  ),
                ),
              ),
            ),

            const SizedBox(height: SFSpacing.md),

            // ── Section label ─────────────────────────────────────────
            if (!_loading && creds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    SFSpacing.base, 0, SFSpacing.base, SFSpacing.sm),
                child: TacticalLabel(
                  _query.isEmpty
                      ? 'ALL CREDENTIALS'
                      : 'RESULTS FOR "$_query"',
                  color: SFColors.textFaint,
                ),
              ),

            // ── Body ─────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? _LoadingSkeleton()
                  : filtered.isEmpty
                      ? _EmptyState(onAdd: _showAddSheet, hasQuery: _query.isNotEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              SFSpacing.base, 0, SFSpacing.base, 110),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: SFSpacing.sm),
                          itemBuilder: (_, i) => _CredentialCard(
                            cred: filtered[i],
                            onEdit: () => _showEditSheet(filtered[i]),
                            onDelete: () => ref
                                .read(credentialProvider.notifier)
                                .remove(filtered[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SFSpacing.base),
      child: Column(
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: SFSpacing.sm),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: SFColors.bgCard,
                borderRadius: BorderRadius.circular(SFRadius.card),
                border: Border.all(color: SFColors.borderSoft),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final bool hasQuery;
  const _EmptyState({required this.onAdd, required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SFSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.key_outlined, size: 36, color: SFColors.textFaint),
            const SizedBox(height: SFSpacing.md),
            Text(
              hasQuery ? 'NO MATCHES FOUND' : SFCopy.passwordsEmpty,
              style: SFTypography.body.copyWith(
                  color: SFColors.textFaint, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (!hasQuery) ...[
              const SizedBox(height: SFSpacing.xl),
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: SFColors.borderMedium),
                    borderRadius: BorderRadius.circular(SFRadius.small),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 14, color: SFColors.textMuted),
                      const SizedBox(width: 6),
                      Text('ADD FIRST CREDENTIAL',
                          style: SFTypography.metadata.copyWith(
                              color: SFColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Credential Card ─────────────────────────────────────────────────────────

class _CredentialCard extends StatefulWidget {
  final Credential cred;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CredentialCard({
    required this.cred,
    required this.onEdit,
    required this.onDelete,
  });

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

  void _copyPassword(BuildContext ctx) {
    Clipboard.setData(ClipboardData(text: widget.cred.password));
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        backgroundColor: SFColors.bgCard,
        duration: const Duration(seconds: 5),
        content: Row(children: [
          const Icon(Icons.content_copy, size: 13, color: SFColors.textMuted),
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

  Future<void> _confirmDelete(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: SFColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFRadius.bento),
          side: const BorderSide(color: SFColors.borderSoft),
        ),
        title: Text('DELETE CREDENTIAL', style: SFTypography.body),
        content: Text(
          'Remove "${widget.cred.website}"? This cannot be undone.',
          style: SFTypography.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: SFTypography.metadata),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('DELETE',
                style: SFTypography.metadata.copyWith(color: SFColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) widget.onDelete();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _clipClearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // First letter avatar colour — always monochrome
    final initials = widget.cred.website.isNotEmpty
        ? widget.cred.website[0].toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        color: SFColors.bgCard,
        borderRadius: BorderRadius.circular(SFRadius.card),
        border: Border.all(color: SFColors.borderSoft),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // ── Left accent bar ───────────────────────────────────────
            Container(
              width: 3,
              decoration: const BoxDecoration(
                color: SFColors.borderMedium,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(SFRadius.card),
                  bottomLeft: Radius.circular(SFRadius.card),
                ),
              ),
            ),

            // ── Avatar ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SFSpacing.md, vertical: SFSpacing.md),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: SFColors.bgPrimary,
                  borderRadius: BorderRadius.circular(SFRadius.small),
                  border: Border.all(color: SFColors.borderSoft),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: SFTypography.cardTitle.copyWith(
                        fontSize: 16, color: SFColors.textMuted),
                  ),
                ),
              ),
            ),

            // ── Site + Username ───────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: SFSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.cred.website,
                      style: SFTypography.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.cred.username,
                      style: SFTypography.terminal.copyWith(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.cred.notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.cred.notes,
                        style: SFTypography.bodyMuted.copyWith(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Actions column ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(SFSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Copy / reveal button
                  GestureDetector(
                    onLongPressStart: _onLongPressStart,
                    onLongPressEnd: _onLongPressEnd,
                    onTap: () => _copyPassword(context),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _holding
                            ? SFColors.borderMedium
                            : SFColors.bgPrimary,
                        borderRadius: BorderRadius.circular(SFRadius.small),
                        border: Border.all(color: SFColors.borderSoft),
                      ),
                      child: _revealed
                          ? Text(widget.cred.password,
                              style: SFTypography.terminal.copyWith(fontSize: 10))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.fingerprint,
                                  size: 13, color: SFColors.textFaint),
                              const SizedBox(width: 3),
                              Text('HOLD',
                                  style: SFTypography.metadata.copyWith(fontSize: 8)),
                            ]),
                    ),
                  ),
                  const SizedBox(height: SFSpacing.xs),
                  // Edit
                  GestureDetector(
                    onTap: widget.onEdit,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: SFColors.bgPrimary,
                        borderRadius: BorderRadius.circular(SFRadius.small),
                        border: Border.all(color: SFColors.borderSoft),
                      ),
                      child: const Icon(Icons.edit_outlined,
                          size: 13, color: SFColors.textFaint),
                    ),
                  ),
                  const SizedBox(height: SFSpacing.xs),
                  // Delete
                  GestureDetector(
                    onTap: () => _confirmDelete(context),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: SFColors.bgPrimary,
                        borderRadius: BorderRadius.circular(SFRadius.small),
                        border: Border.all(color: SFColors.borderSoft),
                      ),
                      child: const Icon(Icons.delete_outline,
                          size: 13, color: SFColors.textFaint),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Credential Sheet ─────────────────────────────────────────────────────

class _AddCredentialSheet extends StatefulWidget {
  final void Function(Credential) onAdd;
  final Credential? existing; // non-null = edit mode
  const _AddCredentialSheet({required this.onAdd, this.existing});

  @override
  State<_AddCredentialSheet> createState() => _AddCredentialSheetState();
}

class _AddCredentialSheetState extends State<_AddCredentialSheet> {
  final _formKey   = GlobalKey<FormState>();
  final _siteCtrl  = TextEditingController();
  final _userCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _passVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-populate for edit mode
    final e = widget.existing;
    if (e != null) {
      _siteCtrl.text  = e.website;
      _userCtrl.text  = e.username;
      _passCtrl.text  = e.password;
      _notesCtrl.text = e.notes;
    }
  }

  @override
  void dispose() {
    _siteCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final cred = Credential(
      website:  _siteCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      notes:    _notesCtrl.text.trim(),
    );
    widget.onAdd(cred);
    // Give the notifier a frame to persist before closing
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(SFSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Sheet header ─────────────────────────────────────
                Row(children: [
                  TacticalLabel(
                    widget.existing != null ? 'EDIT CREDENTIAL' : 'NEW CREDENTIAL',
                    color: SFColors.textMuted,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.close,
                          size: 18, color: SFColors.textFaint),
                    ),
                  ),
                ]),
                const SizedBox(height: SFSpacing.lg),

                // ── Fields ───────────────────────────────────────────
                _SheetField(
                  ctrl: _siteCtrl,
                  label: 'WEBSITE / SERVICE',
                  icon: Icons.language_outlined,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: SFSpacing.md),

                _SheetField(
                  ctrl: _userCtrl,
                  label: 'USERNAME / EMAIL',
                  icon: Icons.person_outline,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: SFSpacing.md),

                // Password with visibility toggle
                TextFormField(
                  controller: _passCtrl,
                  obscureText: !_passVisible,
                  style: SFTypography.terminal.copyWith(
                      fontSize: 14, color: SFColors.textMain),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                  decoration: InputDecoration(
                    labelText: 'PASSWORD',
                    labelStyle: SFTypography.metadata
                        .copyWith(color: SFColors.textFaint),
                    prefixIcon: const Icon(Icons.lock_outline,
                        size: 16, color: SFColors.textFaint),
                    suffixIcon: GestureDetector(
                      onTap: () =>
                          setState(() => _passVisible = !_passVisible),
                      child: Icon(
                        _passVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: SFColors.textFaint,
                      ),
                    ),
                    filled: true,
                    fillColor: SFColors.bgPrimary,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: SFSpacing.md, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SFRadius.small),
                      borderSide: const BorderSide(color: SFColors.borderSoft),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SFRadius.small),
                      borderSide: const BorderSide(color: SFColors.borderSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SFRadius.small),
                      borderSide: const BorderSide(color: SFColors.borderMedium),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SFRadius.small),
                      borderSide: const BorderSide(color: SFColors.danger),
                    ),
                  ),
                ),
                const SizedBox(height: SFSpacing.md),

                _SheetField(
                  ctrl: _notesCtrl,
                  label: 'NOTES (optional)',
                  icon: Icons.notes_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: SFSpacing.xl),

                // ── Save button ──────────────────────────────────────
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 50,
                    decoration: BoxDecoration(
                      color: _saving
                          ? SFColors.borderMedium
                          : SFColors.textMain,
                      borderRadius:
                          BorderRadius.circular(SFRadius.small),
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: SFColors.textFaint))
                          : Text(
                              widget.existing != null
                                  ? 'UPDATE CREDENTIAL'
                                  : 'SAVE TO VAULT',
                              style: SFTypography.button.copyWith(
                                  color: SFColors.bgPrimary)),
                    ),
                  ),
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

class _SheetField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final int maxLines;

  const _SheetField({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      maxLines: maxLines,
      style: SFTypography.body,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            SFTypography.metadata.copyWith(color: SFColors.textFaint),
        prefixIcon: Icon(icon, size: 16, color: SFColors.textFaint),
        filled: true,
        fillColor: SFColors.bgPrimary,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: SFSpacing.md, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.borderMedium),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
          borderSide: const BorderSide(color: SFColors.danger),
        ),
      ),
    );
  }
}
