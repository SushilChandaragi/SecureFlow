/// Analytics Screen — threat intelligence dashboard (§2)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/colors.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../services/vault_provider.dart';
import '../widgets/bento_card.dart';
import '../widgets/tactical_label.dart';
import '../widgets/sf_badge.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: SFColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SFSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TacticalLabel('REAL-TIME MONITORING', color: SFColors.textMuted),
              const SizedBox(height: 6),
              Text(SFCopy.threatIntel, style: SFTypography.h1),
              const SizedBox(height: SFSpacing.xl),

              // ── Metrics row ──────────────────────────────────────
              Row(children: [
                Expanded(
                  child: BentoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TacticalLabel('DEVICE TRUST', color: SFColors.textMuted),
                        const SizedBox(height: SFSpacing.sm),
                        Text('98', style: SFTypography.dataValue),
                        Text('/100', style: SFTypography.bodyMuted.copyWith(fontSize: 11)),
                        const SizedBox(height: 4),
                        const SFBadge('NOMINAL', color: SFColors.success,
                            background: SFColors.successMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SFSpacing.base),
                Expanded(
                  child: BentoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TacticalLabel('FAILED AUTH', color: SFColors.textMuted),
                        const SizedBox(height: SFSpacing.sm),
                        Text('0', style: SFTypography.dataValue),
                        Text('ATTEMPTS', style: SFTypography.bodyMuted.copyWith(fontSize: 11)),
                        const SizedBox(height: 4),
                        const SFBadge('CLEAN'),
                      ],
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: SFSpacing.base),

              // ── Auth method card ─────────────────────────────────
              BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      TacticalLabel('SESSION TELEMETRY', color: SFColors.textMuted),
                      Spacer(),
                      SFBadge('LIVE'),
                    ]),
                    const SizedBox(height: SFSpacing.md),
                    _TelemetryRow('AUTH METHOD', session.profile?.authMethodLabel ?? '—'),
                    _TelemetryRow('SESSION ID', '#${session.profile?.sessionId.substring(0, 8) ?? '——————'}'),
                    _TelemetryRow('SESSION TIME', session.profile?.sessionDuration ?? '00:00:00'),
                    const _TelemetryRow('CRYPTO', 'AES-256-GCM / HKDF-SHA256'),
                    const _TelemetryRow('KEY SIZE', '256-BIT SESSION KEY'),
                    const _TelemetryRow('MEMORY MODE', 'RAM-ONLY, NO DISK WRITES'),
                  ],
                ),
              ),

              const SizedBox(height: SFSpacing.base),

              // ── Dot-matrix location map placeholder ──────────────
              BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TacticalLabel('LAST LOGIN LOCATIONS', color: SFColors.textMuted),
                    const SizedBox(height: SFSpacing.md),
                    SizedBox(
                      height: 80,
                      child: CustomPaint(painter: _DotMatrixPainter()),
                    ),
                    const SizedBox(height: SFSpacing.sm),
                    Text('1 LOCATION — THIS DEVICE',
                        style: SFTypography.metadata.copyWith(fontSize: 9,
                            color: SFColors.textFaint)),
                  ],
                ),
              ),

              const SizedBox(height: SFSpacing.base),

              // ── Monochrome line graph ─────────────────────────────
              BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TacticalLabel('VAULT ACCESS HISTORY', color: SFColors.textMuted),
                    const SizedBox(height: SFSpacing.md),
                    SizedBox(
                      height: 80,
                      child: CustomPaint(painter: _LineGraphPainter()),
                    ),
                    const SizedBox(height: SFSpacing.sm),
                    Row(children: [
                      const Icon(Icons.check_circle_outline, size: 12,
                          color: SFColors.success),
                      const SizedBox(width: 4),
                      Text(SFCopy.analyticsEmpty,
                          style: SFTypography.metadata.copyWith(fontSize: 9)),
                    ]),
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

class _TelemetryRow extends StatelessWidget {
  final String label;
  final String value;
  const _TelemetryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(label, style: SFTypography.metadata.copyWith(fontSize: 9)),
        ),
        Expanded(
          child: Text(value,
              style: SFTypography.terminal.copyWith(fontSize: 10,
                  color: SFColors.textMain)),
        ),
      ]),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SFColors.borderSoft;
    const gap = 8.0;
    for (double x = 0; x < size.width; x += gap) {
      for (double y = 0; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
    // Single device location dot
    canvas.drawCircle(
      Offset(size.width * 0.6, size.height * 0.4),
      4,
      Paint()..color = SFColors.textMain,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _LineGraphPainter extends CustomPainter {
  static const _points = [0.6, 0.5, 0.7, 0.4, 0.6, 0.5, 0.45, 0.55, 0.4, 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    // Grid lines
    final gridPaint = Paint()
      ..color = SFColors.borderSoft
      ..strokeWidth = 0.5;
    for (double y = 0; y <= 1; y += 0.25) {
      canvas.drawLine(Offset(0, y * size.height),
          Offset(size.width, y * size.height), gridPaint);
    }

    // Line graph
    final linePaint = Paint()
      ..color = SFColors.textMuted
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < _points.length; i++) {
      final x = i / (_points.length - 1) * size.width;
      final y = _points[i] * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, linePaint);

    // Fill below
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = SFColors.textMuted.withAlpha(15),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
