import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/paper_color.dart';
import '../theme/app_colors.dart';
import '../theme/paper_style.dart';
import 'paper_painters.dart';

/// Container mô phỏng một tờ giấy thủ công nhỏ dán trên tường hoặc bề mặt.
/// Hỗ trợ đầy đủ 5 màu giấy pastel (nhận từ domain PaperColor), 2 kiểu ghim/băng dính
/// và biến thiên tất định theo styleSeed.
/// Giữ tương thích 100% với constructor cũ và các màn hình hiện có.
class PaperSheet extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final PaperColor? paperColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool showTape;
  final PaperAttachmentType? attachment;
  final int? styleSeed;
  final bool applyRotation;

  const PaperSheet({
    super.key,
    required this.child,
    this.backgroundColor = AppColors.paperSurface,
    this.paperColor,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 14,
    this.showTape = false,
    this.attachment,
    this.styleSeed,
    this.applyRotation = false,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Xác định màu nền: Ưu tiên domain PaperColor nếu có, fallback về backgroundColor
    final Color effectiveBg = paperColor != null
        ? AppColors.colorForPaper(paperColor!)
        : backgroundColor;

    // 2. Xác định kiểu đính kèm và góc xoay từ styleSeed hoặc tham số truyền vào
    final PaperDeterministicStyle? style =
        styleSeed != null ? PaperDeterministicStyle.fromSeed(styleSeed!) : null;

    final PaperAttachmentType effectiveAttachment = attachment ??
        style?.attachmentType ??
        (showTape ? PaperAttachmentType.tape : PaperAttachmentType.none);

    final double effectiveTapeAngle = style?.attachmentAngleDeg ?? 0.0;
    final double effectiveRotation = applyRotation ? (style?.rotationDeg ?? 0.0) : 0.0;

    // 3. Xây dựng tờ giấy
    Widget sheet = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AppColors.paperBorder,
          width: 1,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // 2 kiểu đính kèm: Băng dính (Tape) hoặc Ghim tròn (Pin)
          if (effectiveAttachment == PaperAttachmentType.tape)
            Positioned(
              top: -8,
              child: CustomPaint(
                size: const Size(40, 15),
                painter: TapePainter(angleDeg: effectiveTapeAngle),
              ),
            )
          else if (effectiveAttachment == PaperAttachmentType.pin)
            const Positioned(
              top: -10,
              child: CustomPaint(
                size: const Size(20, 20),
                painter: PinPainter(),
              ),
            ),
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );

    // 4. Nếu yêu cầu xoay tất định (áp dụng trên tường thế giới Flame/Wall preview)
    if (effectiveRotation != 0.0) {
      sheet = Transform.rotate(
        angle: effectiveRotation * math.pi / 180,
        child: sheet,
      );
    }

    return sheet;
  }
}
