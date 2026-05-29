/// NavPill — floating glassmorphic segmented navigation (§9)
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/colors.dart';

enum NavTab { vault, keys, shield, folder, gear }

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
    (NavTab.keys,   Icons.key_outlined,      'Passwords'),
    (NavTab.shield, Icons.shield_outlined,   'MFA Codes'),
    (NavTab.folder, Icons.folder_outlined,   'Docs'),
    (NavTab.gear,   Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SFRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            // Multi-layer glass: very subtle white tint over pure black
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withAlpha(18),
                Colors.white.withAlpha(8),
              ],
            ),
            borderRadius: BorderRadius.circular(SFRadius.pill),
            border: Border.all(
              color: Colors.white.withAlpha(30),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.white.withAlpha(5),
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
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
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white.withAlpha(25)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(SFRadius.pill),
                      border: isActive
                          ? Border.all(
                              color: Colors.white.withAlpha(40),
                              width: 0.6,
                            )
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: isActive
                          ? SFColors.textMain
                          : SFColors.textFaint.withAlpha(160),
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
