/// BentoCard — core reusable container (§4 Component Hierarchy)
///
/// #111111 background, 28px border radius, 1px rgba(255,255,255,0.08) border.
library;

import 'package:flutter/material.dart';
import '../config/colors.dart';

class BentoCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? borderRadius;
  final VoidCallback? onTap;
  final bool elevated;
  final Color? backgroundColor;

  const BentoCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.elevated = false,
    this.backgroundColor,
  });

  @override
  State<BentoCard> createState() => _BentoCardState();
}

class _BentoCardState extends State<BentoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _elevateCtrl;
  late Animation<double> _elevateAnim;

  @override
  void initState() {
    super.initState();
    _elevateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _elevateAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _elevateCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _elevateCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _elevateCtrl.forward();
  void _onTapUp(_) => _elevateCtrl.reverse();
  void _onTapCancel() => _elevateCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? SFRadius.bento;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      child: AnimatedBuilder(
        animation: _elevateAnim,
        builder: (_, child) => Transform.translate(
          // Magnetic hover: card lifts 3px on press (§5 animation)
          offset: Offset(0, -3 * _elevateAnim.value),
          child: child,
        ),
        child: Container(
          padding: widget.padding ?? const EdgeInsets.all(SFSpacing.md),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? SFColors.bgCard,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: SFColors.borderSoft,
              width: 1,
            ),
            boxShadow: widget.elevated
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(120),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
