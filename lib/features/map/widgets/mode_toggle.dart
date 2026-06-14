import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/walk_mode.dart';

/// 日陰優先 / 日向優先 の切替トグル（自前実装・アイコン＋文字、潰れない）。
class ModeToggle extends StatelessWidget {
  const ModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final WalkMode mode;
  final ValueChanged<WalkMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(30),
      color: Colors.white,
      shadowColor: AppColors.plum.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment(
              selected: mode == WalkMode.shade,
              icon: Icons.dark_mode_outlined,
              label: '日陰',
              onTap: () => onChanged(WalkMode.shade),
              activeColor: AppColors.plum,
            ),
            _segment(
              selected: mode == WalkMode.sun,
              icon: Icons.wb_sunny_outlined,
              label: '日向',
              onTap: () => onChanged(WalkMode.sun),
              activeColor: AppColors.gold,
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    final fg = selected ? Colors.white : AppColors.mist;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
