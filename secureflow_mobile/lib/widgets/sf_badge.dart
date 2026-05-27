/// SFBadge — classification tag or status badge
library;

import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../config/typography.dart';

class SFBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? background;

  const SFBadge(
    this.label, {
    super.key,
    this.color,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? SFColors.borderSoft,
        borderRadius: BorderRadius.circular(SFRadius.small),
        border: Border.all(color: SFColors.borderSoft, width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: SFTypography.metadata.copyWith(
          color: color ?? SFColors.textMuted,
          fontSize: 9,
        ),
      ),
    );
  }
}
