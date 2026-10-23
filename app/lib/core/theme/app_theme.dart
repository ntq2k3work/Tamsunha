import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Cấu hình ThemeData của Tường Nhỏ.
/// Contract cho router và MaterialApp ráp sau.
abstract final class AppTheme {
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.ink,
      onPrimary: AppColors.paperSurface,
      secondary: AppColors.inkSecondary,
      onSecondary: AppColors.paperSurface,
      surface: AppColors.canvas,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      cardColor: AppColors.paperSurface,
      dividerColor: AppColors.paperBorder,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      
      // AppBar phong cách giấy tối giản, không viền bóng
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.titleLarge,
      ),

      // Thanh điều hướng Shell (Navigation Bar) phong cách giấy
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.paperSurface,
        elevation: 0,
        indicatorColor: AppColors.tape,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.labelLarge.copyWith(fontSize: 12);
          }
          return AppTypography.bodySmall;
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.ink, size: 24);
          }
          return const IconThemeData(color: AppColors.inkSecondary, size: 24);
        }),
      ),

      // Theme nút bấm: tối thiểu 44dp tap target
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.paperSurface,
          minimumSize: const Size(48, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: AppTypography.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.ink, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: AppTypography.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(44, 44),
          textStyle: AppTypography.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),

      // Card phong cách tờ giấy mềm mại
      cardTheme: CardThemeData(
        color: AppColors.paperSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.paperBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}
