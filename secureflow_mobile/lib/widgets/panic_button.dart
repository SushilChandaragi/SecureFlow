/// PanicButton — high-visibility danger-zone action button
library;

import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../config/typography.dart';

class PanicButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const PanicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: SFColors.dangerMuted,
          borderRadius: BorderRadius.circular(SFRadius.small),
          border: Border.all(color: SFColors.danger, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: SFColors.danger, size: 16),
              const SizedBox(width: 8),
            ],
            Text(
              label.toUpperCase(),
              style: SFTypography.danger,
            ),
          ],
        ),
      ),
    );
  }
}
