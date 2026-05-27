/// Splash Screen — "INITIALIZING SECURE ENCLAVE..." (§2 Screen-by-Screen)
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _glyphCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _glyphOpacity;
  late Animation<double> _pulseOpacity;

  final _rng = Random();
  String _glyphText = '';
  Timer? _glyphTimer;
  bool _showLogo = false;
  bool _showFooter = false;

  // Static noise overlay characters
  static const _noise =
      'ABCDEFabcdef0123456789!@#\$%^&*()_+-=[]{}|;:,.<>?/~`';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _glyphCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _glyphOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _glyphCtrl, curve: Curves.easeIn),
    );
    _pulseOpacity = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _startGlyphAnimation();
  }

  void _startGlyphAnimation() {
    // Phase 1: Random crypto chars for 1.2s
    _glyphTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(() {
        _glyphText = List.generate(
          8,
          (_) => _noise[_rng.nextInt(_noise.length)],
        ).join();
      });
    });

    // Phase 2: Reveal logo at 1.2s
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _glyphTimer?.cancel();
      _glyphCtrl.forward();
      setState(() {
        _showLogo = true;
        _glyphText = 'SF';
      });
    });

    // Phase 3: Show footer at 1.6s
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _showFooter = true);
    });

    // Phase 4: Navigate at 3.0s
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _glyphTimer?.cancel();
    _glyphCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      body: Stack(
        children: [
          // ── Static noise overlay ─────────────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _NoisePainter(_rng)),
          ),

          // ── Center glyph ─────────────────────────────────────────
          Center(
            child: _showLogo
                ? FadeTransition(
                    opacity: _glyphOpacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo mark
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: SFColors.textMuted,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              'SF',
                              style: SFTypography.h1.copyWith(
                                fontSize: 28,
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'SECUREFLOW',
                          style: SFTypography.metadata.copyWith(
                            letterSpacing: 8,
                            color: SFColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    _glyphText,
                    style: SFTypography.h1.copyWith(
                      letterSpacing: 12,
                      color: SFColors.textMuted,
                    ),
                  ),
          ),

          // ── Pulsing footer ───────────────────────────────────────
          if (_showFooter)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _pulseOpacity,
                builder: (_, __) => Opacity(
                  opacity: _pulseOpacity.value,
                  child: Text(
                    SFCopy.initializingEnclave,
                    textAlign: TextAlign.center,
                    style: SFTypography.metadata.copyWith(
                      letterSpacing: 3,
                      color: SFColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Custom painter for static noise overlay ──────────────────────────────────
class _NoisePainter extends CustomPainter {
  final Random rng;
  _NoisePainter(this.rng);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SFColors.textMain.withAlpha(3);
    for (var i = 0; i < 1200; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          rng.nextDouble() * size.width,
          rng.nextDouble() * size.height,
          1.5,
          1.5,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
