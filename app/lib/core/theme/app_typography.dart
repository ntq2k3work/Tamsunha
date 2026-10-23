import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Kiểu chữ ấm áp, mềm mại theo phong cách chibi editorial của Tường Nhỏ.
/// Không phụ thuộc package font ngoài, tương thích hoàn toàn với hệ thống text scaling.
abstract final class AppTypography {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    letterSpacing: -0.5,
    height: 1.3,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    letterSpacing: -0.3,
    height: 1.35,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.4,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    height: 1.45,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.inkSecondary,
    height: 1.4,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    letterSpacing: 0.2,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.inkLight,
    height: 1.3,
  );
}
