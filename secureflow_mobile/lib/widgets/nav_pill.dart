/// NavPill — floating glassmorphic segmented navigation (§9)
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/colors.dart';

enum NavTab { vault, keys, shield, gear }

class NavPill extends StatelessWidget {
  final NavTab current;
  final ValueChanged<NavTab> onTabChanged;

  const NavPill({
    super.key,
    required this.current,
    required this.onTabChanged,
  });

  static const _tabs = [
    (NavTab.vault,  Icons.lock_outline,      'Vault'),
    (NavTab.keys,   Icons.key_outlined,      'Keys'),
    (NavTab.shield, Icons.shield_outlined,   'Shield'),
    (NavTab.gear,   Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SFRadius.pill),
      child: BackdropFilter(
        // Glassmorphism blur (§10 Flutter Suggestions)
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: SFColors.bgCard.withAlpha(200),
            borderRadius: BorderRadius.circular(SFRadius.pill),
            border: Border.all(color: SFColors.borderMedium, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _tabs.map((entry) {
              final (tab, icon, tooltip) = entry;
              final isActive = tab == current;
              return Tooltip(
                message: tooltip,
                child: GestureDetector(
                  onTap: () => onTabChanged(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? SFColors.textMain.withAlpha(20)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(SFRadius.pill),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: isActive
                          ? SFColors.textMain
                          : SFColors.textFaint,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
