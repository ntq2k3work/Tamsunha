import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Nút bấm phong cách tờ giấy mềm mại với vùng chạm tối thiểu 44dp.
class PaperButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isPrimary;
  final Color? backgroundColor;

  const PaperButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final effectiveBg = !isEnabled
        ? AppColors.disabled
        : (backgroundColor ?? (isPrimary ? AppColors.ink : AppColors.paperSurface));
    final effectiveFg = !isEnabled
        ? AppColors.inkSecondary
        : (isPrimary ? AppColors.paperSurface : AppColors.ink);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 44,
        minWidth: 44,
      ),
      child: Material(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isPrimary ? Colors.transparent : AppColors.paperBorder,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: effectiveFg),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(color: effectiveFg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
