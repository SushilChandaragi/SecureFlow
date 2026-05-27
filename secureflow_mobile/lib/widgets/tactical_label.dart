/// TacticalLabel — uppercase, wide-spaced metadata text (§4 Component Hierarchy)
library;

import 'package:flutter/material.dart';
import '../config/typography.dart';

class TacticalLabel extends StatelessWidget {
  final String text;
  final Color? color;
  final double? fontSize;

  const TacticalLabel(
    this.text, {
    super.key,
    this.color,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    var style = SFTypography.metadata;
    if (color != null) style = style.copyWith(color: color);
    if (fontSize != null) style = style.copyWith(fontSize: fontSize);
    return Text(text.toUpperCase(), style: style);
  }
}
