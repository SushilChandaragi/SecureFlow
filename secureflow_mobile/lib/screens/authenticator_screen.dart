/// Authenticator Screen — horizontal TOTP carousel (§2)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/totp_key.dart';
import '../services/vault_provider.dart';
import '../services/totp_service.dart';
import '../widgets/tactical_label.dart';
import '../widgets/totp_ring.dart';

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

  @override
  Widget build(BuildContext context) {
    final totps = ref.watch(totpProvider);

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
                  const TacticalLabel('IDENTITY TOKENS', color: SFColors.textMuted),
                  const SizedBox(height: 6),
                  Text('AUTHENTICATOR', style: SFTypography.h1),
                ],
              ),
            ),

            if (totps.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 36,
                          color: SFColors.textFaint),
                      SizedBox(height: SFSpacing.sm),
                      TacticalLabel(SFCopy.totpEmpty, color: SFColors.textFaint),
                    ],
                  ),
                ),
              )
            else ...[
              // Horizontal carousel
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
                  ),
                ),
              ),
              // Page dots
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

class _TotpCard extends StatelessWidget {
  final TotpKey totpKey;
  final int remaining;

  const _TotpCard({super.key, required this.totpKey, required this.remaining});

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
            TactualLabel(totpKey.displayName.toUpperCase(), color: SFColors.textMuted),
            const SizedBox(height: 4),
            Text(totpKey.metaLine, style: SFTypography.bodyMuted.copyWith(fontSize: 11)),
            const SizedBox(height: SFSpacing.xl),
            // TOTP ring + massive code
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
                    child: Text(
                      formatted,
                      style: SFTypography.totpCode,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SFSpacing.md),
            // Countdown line
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

// Minor typo guard - alias
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
