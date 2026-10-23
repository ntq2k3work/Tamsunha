import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../../../core/domain/note_tile.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/paper_style.dart';
import '../domain/wall_geometry.dart';

final class WallNoteComponent extends PositionComponent with TapCallbacks {
  WallNoteComponent({
    required this.note,
    required Vector2 position,
    required this.onOpen,
    this.reducedMotion = false,
    this.isInteractive = true,
  })  : style = PaperDeterministicStyle.fromSeed(note.styleSeed),
        _baseX = position.x,
        _baseY = position.y,
        super(
          position: position,
          size: Vector2(
            WallGeometry.noteWidthWorldUnits,
            WallGeometry.noteHeightWorldUnits,
          ),
          anchor: Anchor.center,
        ) {
    angle = style.rotationDeg * math.pi / 180;
  }

  final NoteTile note;
  final PaperDeterministicStyle style;
  final ValueChanged<NoteTile> onOpen;
  final bool reducedMotion;
  bool isInteractive;
  double _baseX;
  double _baseY;
  double _elapsed = 0;

  void setWallPosition(Vector2 nextPosition) {
    _baseX = nextPosition.x;
    _baseY = nextPosition.y;
    position.setFrom(nextPosition);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (reducedMotion) return;
    _elapsed += dt;
    final phase = (note.styleSeed % 628) / 100 + _elapsed * 1.35;
    angle = style.rotationDeg * math.pi / 180 + math.sin(phase) * 0.006;
    position.setValues(_baseX, _baseY + math.sin(phase * 0.7) * 0.8);
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (isInteractive) onOpen(note);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final rect = Rect.fromCenter(
      center: Offset(size.x / 2, size.y / 2),
      width: size.x,
      height: size.y,
    );
    final paper = Path()
      ..moveTo(rect.left + 4, rect.top)
      ..lineTo(rect.right - 3, rect.top + 2)
      ..lineTo(rect.right, rect.bottom - 4)
      ..lineTo(rect.left + 2, rect.bottom)
      ..close();

    canvas.drawPath(
      paper.shift(const Offset(1.5, 3)),
      Paint()..color = const Color(0x1F55483E),
    );
    canvas.drawPath(paper, Paint()..color = AppColors.colorForPaper(note.paperColor));
    canvas.drawPath(
      paper,
      Paint()
        ..color = const Color(0x3355483E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    _paintAttachment(canvas);
    _paintUnreadableDoodle(canvas);
  }

  void _paintAttachment(Canvas canvas) {
    if (style.attachmentType == PaperAttachmentType.pin) {
      final center = Offset(size.x * 0.5, 3);
      canvas.drawCircle(
        center.translate(1, 2),
        7,
        Paint()..color = const Color(0x3355483E),
      );
      canvas.drawCircle(center, 7, Paint()..color = const Color(0xFFCE8E82));
      canvas.drawCircle(
        center.translate(-2, -2),
        2,
        Paint()..color = const Color(0x99FFFFFF),
      );
      return;
    }

    canvas.save();
    canvas.translate(size.x * 0.5, 7);
    canvas.rotate(style.attachmentAngleDeg * math.pi / 180);
    final tape = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 42, height: 12),
      const Radius.circular(2),
    );
    canvas.drawRRect(tape, Paint()..color = const Color(0xBFEBDCBA));
    canvas.restore();
  }

  void _paintUnreadableDoodle(Canvas canvas) {
    // These seed-based strokes are decorative marks, never note content.
    final paint = Paint()
      ..color = const Color(0x6655483E)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.1;
    final seed = note.styleSeed;
    final top = size.y * 0.34;
    for (var row = 0; row < 4; row++) {
      final widthFactor = 0.42 + (((seed >> (row * 3)) & 7) / 28);
      final left = size.x * (0.18 + ((seed >> (row + 1)) & 3) * 0.012);
      final width = size.x * widthFactor;
      final baseline = top + row * 15;
      final path = Path()
        ..moveTo(left, baseline)
        ..cubicTo(
          left + width * 0.28,
          baseline - 3,
          left + width * 0.55,
          baseline + 2,
          left + width,
          baseline - 1,
        );
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(
      Offset(size.x * 0.77, size.y * 0.81),
      5,
      Paint()..color = const Color(0x55977870),
    );
  }
}

final class WallTileClusterComponent extends PositionComponent with TapCallbacks {
  WallTileClusterComponent({
    required this.notes,
    required Vector2 position,
    required this.onOpenRegion,
  }) : super(position: position, size: Vector2.all(48), anchor: Anchor.center);

  final List<NoteTile> notes;
  final VoidCallback onOpenRegion;

  @override
  void onTapUp(TapUpEvent event) => onOpenRegion();

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final color = AppColors.colorForPaper(notes.first.paperColor);
    final center = Offset(size.x / 2, size.y / 2);
    final radius = math.min(22.0, 9 + math.sqrt(notes.length) * 1.2);
    canvas.drawCircle(center, radius + 3, Paint()..color = const Color(0x2255483E));
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x6655483E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (notes.length > 1) {
      final text = TextPainter(
        text: TextSpan(
          text: notes.length > 99 ? '99+' : '${notes.length}',
          style: const TextStyle(
            color: Color(0xFF55483E),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
  }
}

final class WallGhostComponent extends PositionComponent {
  WallGhostComponent({
    required Vector2 position,
    required this.paperColor,
    required this.isOccupied,
  }) : super(
          position: position,
          size: Vector2(
            WallGeometry.noteWidthWorldUnits,
            WallGeometry.noteHeightWorldUnits,
          ),
          anchor: Anchor.center,
        );

  PaperColor paperColor;
  bool isOccupied;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final rect = Rect.fromLTWH(2, 2, size.x - 4, size.y - 4);
    final color = isOccupied ? AppColors.danger : AppColors.colorForPaper(paperColor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = color.withValues(alpha: 0.58),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = isOccupied
            ? const Color(0xFFD6726F)
            : const Color(0xFF977E70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
