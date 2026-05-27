/// Password Vault Screen — hold-to-reveal credentials (§2)
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

  @override
  Widget build(BuildContext context) {
    final creds = ref.watch(credentialProvider);
    final filtered = creds.where((c) =>
      c.website.toLowerCase().contains(_query.toLowerCase()) ||
      c.username.toLowerCase().contains(_query.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
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
                  // Monolithic search bar
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
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.key_outlined, size: 32,
                              color: SFColors.textFaint),
                          SizedBox(height: SFSpacing.sm),
                          TacticalLabel(SFCopy.passwordsEmpty,
                              color: SFColors.textFaint),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          SFSpacing.base, 0, SFSpacing.base, 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: SFSpacing.base),
                      itemBuilder: (_, i) => _CredentialCard(cred: filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    // Auto-clear clipboard after 5s
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
          // Grayscale favicon placeholder
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
          // Hold to reveal zone
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
