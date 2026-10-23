import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/paper_sheet.dart';

/// Màn hình Splash/Bootstrap (S00) — Khởi tạo ứng dụng & kiểm tra phiên.
class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: PaperSheet(
            showTape: true,
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 48,
                  color: AppColors.ink,
                ),
                SizedBox(height: 16),
                Text(
                  'Tường Nhỏ',
                  style: AppTypography.displayLarge,
                ),
                SizedBox(height: 8),
                Text(
                  'Gửi gắm tâm tư vào một tờ giấy nhỏ',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall,
                ),
                SizedBox(height: 28),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.inkSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
