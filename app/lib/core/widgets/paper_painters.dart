import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Painter vẽ băng dính washitape mờ với 2 mép rách răng cưa thủ công.
class TapePainter extends CustomPainter {
  final double angleDeg;
  final Color color;

  const TapePainter({
    this.angleDeg = 0.0,
    this.color = const Color(0xD9EBDCBA),
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angleDeg * math.pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Đường path mô phỏng dải băng dính có 2 đầu mép xé răng cưa nhẹ
    final path = Path();
    path.moveTo(0, 0);

    // Mép trên
    path.lineTo(w, 0);

    // Mép phải: răng cưa xé giấy
    path.lineTo(w - 2, h * 0.3);
    path.lineTo(w + 1, h * 0.6);
    path.lineTo(w - 1, h);

    // Mép dưới
    path.lineTo(0, h);

    // Mép trái: răng cưa xé giấy
    path.lineTo(1, h * 0.7);
    path.lineTo(-2, h * 0.4);
    path.close();

    canvas.drawPath(path, paint);

    // Đường viền rất nhạt tạo cảm giác gờ băng dính
    final borderPaint = Paint()
      ..color = const Color(0x2255483E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(path, borderPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TapePainter oldDelegate) {
    return oldDelegate.angleDeg != angleDeg || oldDelegate.color != color;
  }
}

/// Painter vẽ ghim tròn chibi (Pushpin) có bóng đổ và điểm sáng nổi khối nhẹ.
class PinPainter extends CustomPainter {
  final Color pinColor;

  const PinPainter({
    this.pinColor = const Color(0xFFD6726F), // Màu đỏ đất chibi ấm áp
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) * 0.75;

    // 1. Bóng đổ nghiêng nhẹ của ghim
    final shadowPaint = Paint()
      ..color = const Color(0x3355483E)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 1.2, cy + 2.0),
        width: radius * 1.9,
        height: radius * 1.5,
      ),
      shadowPaint,
    );

    // 2. Thân mũ ghim tròn
    final headPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), radius, headPaint);

    // 3. Viền mảnh tạo chiều sâu
    final outlinePaint = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(Offset(cx, cy), radius, outlinePaint);

    // 4. Vệt sáng highlight hình bán nguyệt ở góc trên bên trái
    final highlightPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(cx - radius * 0.32, cy - radius * 0.32),
      radius * 0.35,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant PinPainter oldDelegate) {
    return oldDelegate.pinColor != pinColor;
  }
}

/// Painter vẽ vân giấy tĩnh lặp liền mạch (Seamless Paper Texture).
/// Sử dụng các hạt vi mô tính toán tất định theo chu kỳ lưới, không dùng ảnh bitmap.
class SeamlessPaperPatternPainter extends CustomPainter {
  static final Paint _grainPaint = Paint()
    ..color = const Color(0x0A55483E) // ~4% opacity của màu mực
    ..style = PaintingStyle.fill;

  static final Paint _fiberPaint = Paint()
    ..color = const Color(0x0655483E) // ~2.5% opacity cho sợi giấy
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;

  const SeamlessPaperPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Bước nhảy ô lưới lặp liền mạch: 32 logical units
    const double step = 32.0;
    final cols = (size.width / step).ceil();
    final rows = (size.height / step).ceil();

    for (int r = 0; r < rows; r++) {
      final y = r * step;
      for (int c = 0; c < cols; c++) {
        final x = c * step;

        // Sinh vị trí vi sợi tĩnh dựa trên tọa độ ô
        final hash = ((c * 73856093) ^ (r * 19349663)) & 0xFFFF;
        final offsetX = (hash % 24).toDouble();
        final offsetY = ((hash >> 4) % 24).toDouble();

        // Chấm hạt giấy
        canvas.drawCircle(Offset(x + offsetX, y + offsetY), 0.75, _grainPaint);

        // Sợi xơ giấy siêu ngắn (2-3px) ngẫu nhiên tĩnh
        if (hash % 3 == 0) {
          final fx = x + ((hash >> 2) % 20);
          final fy = y + ((hash >> 6) % 20);
          canvas.drawLine(
            Offset(fx, fy),
            Offset(fx + 2.2, fy + 1.2),
            _fiberPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SeamlessPaperPatternPainter oldDelegate) => false;
}
