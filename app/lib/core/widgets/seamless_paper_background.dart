import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'paper_painters.dart';

/// Bề mặt nền mô phỏng giấy thủ công với vân hạt lặp liền mạch tĩnh.
/// Không tốn dung lượng tải ảnh, không gây giật lag và không có motion liên tục.
class SeamlessPaperBackground extends StatelessWidget {
  final Widget? child;
  final Color backgroundColor;

  const SeamlessPaperBackground({
    super.key,
    this.child,
    this.backgroundColor = AppColors.canvas,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: CustomPaint(
        painter: const SeamlessPaperPatternPainter(),
        isComplex: false,
        willChange: false,
        child: child,
      ),
    );
  }
}
