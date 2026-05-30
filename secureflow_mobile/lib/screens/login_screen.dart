/// Hardware Login Screen — Biometric + NFC authentication (§2)
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../services/vault_provider.dart';
import '../widgets/bento_card.dart';
import '../widgets/tactical_label.dart';
import '../widgets/hex_loader.dart';
import '../utils/logger.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  const LoginScreen({super.key, required this.onUnlocked});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _nfcPulseCtrl;
  late Animation<double> _nfcPulse;

  bool _isAuthenticating = false;
  bool _isNfcScanning = false;
  bool _nfcConsumed   = false; // debounce: ignore subsequent NFC callbacks
  String _statusText = SFCopy.identityRequired;

  double _waveOffset = 0;
  Timer? _waveTimer;

  @override
  void initState() {
    super.initState();
    _nfcPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _nfcPulse = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _nfcPulseCtrl, curve: Curves.easeInOut),
    );

    _waveTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      setState(() => _waveOffset += 0.05);
    });
  }

  @override
  void dispose() {
    _nfcPulseCtrl.dispose();
    _waveTimer?.cancel();
    super.dispose();
  }

  Future<void> _onBiometricTap() async {
    if (_isAuthenticating) return;
    sfLog('LoginScreen: biometric tap');
    final auth = ref.read(authServiceProvider);
    final available = await auth.isBiometricAvailable();
    if (!mounted) return;
    sfLog('LoginScreen: biometric available=$available');
    if (!available) {
      setState(() {
        _isAuthenticating = false;
        _statusText = 'BIOMETRIC NOT AVAILABLE — ENROLL FINGERPRINT';
      });
      return;
    }
    setState(() {
      _isAuthenticating = true;
      _statusText = 'VERIFYING BIOMETRIC...';
    });
    final ok = await ref.read(sessionProvider.notifier).unlockWithBiometric(auth);
    sfLog('LoginScreen: biometric result=$ok');
    if (!mounted) return;
    if (ok) {
      sfLog('LoginScreen: navigating to dashboard');
      widget.onUnlocked();
    } else {
      setState(() {
        _isAuthenticating = false;
        _statusText = SFCopy.authFail;
      });
    }
  }

  Future<void> _onNfcTap() async {
    if (_isNfcScanning) return;
    sfLog('LoginScreen: NFC tap');
    final auth = ref.read(authServiceProvider);
    final available = await auth.isNfcAvailable();
    if (!mounted) return;
    sfLog('LoginScreen: NFC available=$available');
    if (!available) {
      setState(() => _statusText = 'NFC NOT AVAILABLE ON THIS DEVICE');
      return;
    }
    setState(() {
      _isNfcScanning = true;
      _nfcConsumed   = false;   // reset for new scan
      _statusText = SFCopy.awaitingNfc;
    });
    auth.startNfcSession(
      onPayload: (Uint8List payload) {
        if (_nfcConsumed) return;  // ignore extra callbacks from tag staying in field
        _nfcConsumed = true;
        if (!mounted) return;
        // Decode the raw payload as UTF-8 text (what the NFC Tools app wrote)
        final tagText = _payloadToString(payload);
        sfLog('LoginScreen: NFC text="$tagText"');
        ref.read(sessionProvider.notifier).unlockWithNfcString(tagText).then((ok) {
          if (!mounted) return;
          sfLog('LoginScreen: NFC unlock result=$ok');
          if (ok) widget.onUnlocked();
          setState(() {
            _isNfcScanning = false;
            _statusText = ok ? SFCopy.unlocked : SFCopy.authFail;
          });
        });
      },
      onError: (error) {
        if (!mounted) return;
        sfLog('LoginScreen: NFC error=$error');
        String message = 'NFC ERROR';
        if (error.contains('NFC_UNAVAILABLE')) {
          message = 'NFC NOT AVAILABLE ON THIS DEVICE';
        } else if (error.contains('NFC_EMPTY_TAG')) {
          message = 'NFC TAG EMPTY — WRITE SECRET';
        } else if (error.contains('NFC_READ_ERROR')) {
          message = 'NFC READ FAILED';
        } else if (error.contains('NFC_SESSION_ERROR')) {
          message = 'NFC SESSION ERROR';
        }
        setState(() {
          _isNfcScanning = false;
          _statusText = message;
        });
      },
    );
  }

  /// Decode NDEF text record bytes → plain string.
  /// Since auth_service.dart's _extractPayload already strips the NDEF header and language code,
  /// the payload here is the raw string bytes (potentially zero-padded to 32 bytes).
  String _payloadToString(Uint8List payload) {
    try {
      if (payload.isEmpty) return '';
      // Filter out any zero padding / null bytes
      final cleanBytes = payload.where((b) => b != 0).toList();
      return utf8.decode(cleanBytes).trim();
    } catch (_) {
      final cleanBytes = payload.where((b) => b != 0).toList();
      return String.fromCharCodes(cleanBytes).trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(SFSpacing.base),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: SFSpacing.xl),
              const TacticalLabel(SFCopy.identityRequired, color: SFColors.textMuted, fontSize: 11),
              const SizedBox(height: SFSpacing.sm),
              Text('SECUREFLOW', style: SFTypography.h1),
              const SizedBox(height: SFSpacing.xl),
              SizedBox(
                height: 40,
                child: CustomPaint(painter: _WavePainter(_waveOffset)),
              ),
              const SizedBox(height: SFSpacing.xl),
              // Biometric card
              BentoCard(
                onTap: _onBiometricTap,
                elevated: true,
                child: Column(
                  children: [
                    const SizedBox(height: SFSpacing.md),
                    Icon(Icons.fingerprint, size: 72,
                        color: _isAuthenticating ? SFColors.success : SFColors.textMuted),
                    const SizedBox(height: SFSpacing.md),
                    const TacticalLabel(SFCopy.awaitingBio, color: SFColors.textMuted),
                    const SizedBox(height: SFSpacing.sm),
                    if (session.isLoading)
                      const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 1, color: SFColors.textMuted))
                    else
                      Text('TAP TO AUTHENTICATE', style: SFTypography.metadata),
                    const SizedBox(height: SFSpacing.md),
                  ],
                ),
              ),
              const SizedBox(height: SFSpacing.base),
              // NFC card
              AnimatedBuilder(
                animation: _nfcPulse,
                builder: (_, child) => Opacity(
                  opacity: _isNfcScanning ? _nfcPulse.value : 1.0,
                  child: child,
                ),
                child: BentoCard(
                  onTap: _onNfcTap,
                  child: Row(
                    children: [
                      Icon(Icons.nfc, size: 28,
                          color: _isNfcScanning ? SFColors.success : SFColors.textMuted),
                      const SizedBox(width: SFSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TacticalLabel(
                              _isNfcScanning ? SFCopy.awaitingNfc : 'NFC KEY AUTHENTICATION',
                              color: SFColors.textMuted,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isNfcScanning ? 'BRING NFC TAG NEAR DEVICE...' : 'TAP TO SCAN NFC SECURITY TAG',
                              style: SFTypography.bodyMuted.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (_isNfcScanning)
                        const SizedBox(height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 1, color: SFColors.success)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SFSpacing.lg),
              Center(
                child: Text(_statusText,
                    style: SFTypography.metadata.copyWith(
                        color: session.isError ? SFColors.danger : SFColors.textFaint)),
              ),
              const SizedBox(height: SFSpacing.base),
              if (_isAuthenticating)
                const HexLoader(bootSequence: SFCopy.cryptoBootSequence, showSequence: true),
              const SizedBox(height: SFSpacing.md),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double offset;
  _WavePainter(this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    for (int w = 0; w < 3; w++) {
      final paint = Paint()
        ..color = SFColors.textFaint.withAlpha(80 - w * 25)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(0, size.height / 2);
      for (double x = 0; x <= size.width; x++) {
        final y = size.height / 2 + sin(x / 20 + offset + w * 1.5) * (8 - w * 2);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.offset != offset;
}
