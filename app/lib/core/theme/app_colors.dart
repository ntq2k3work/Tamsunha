import 'package:flutter/material.dart';
import '../domain/paper_color.dart';

/// Bảng màu chuẩn theo đặc tả UX Tường Nhỏ (ALL_IN_ONE_SPEC.md - Section 3.1).
/// Tone: Chibi editorial, giấy thủ công, ấm áp, không bóng nhựa, không neon.
abstract final class AppColors {
  // Nền thế giới & bề mặt chính
  static const Color canvas = Color(0xFFF3E8D7);
  static const Color paperSurface = Color(0xFFFAF5EC);
  static const Color paperBorder = Color(0xFFE5D7C3);
  static const Color tape = Color(0xFFEBDCBA);

  // Mực viết (Ink tokens)
  static const Color ink = Color(0xFF55483E);
  static const Color inkSecondary = Color(0xFF82756A);
  static const Color inkLight = Color(0xFFA6978A);

  // 5 màu giấy pastel chính thức
  static const Color pink = Color(0xFFF4D5D8);
  static const Color butter = Color(0xFFF8E5B2);
  static const Color sage = Color(0xFFDCE7D6);
  static const Color blue = Color(0xFFDAE6F1);
  static const Color lilac = Color(0xFFE9E0F3);

  // Màu trạng thái & hành động
  static const Color danger = Color(0xFFC9605E);
  static const Color success = Color(0xFF7E9E78);
  static const Color disabled = Color(0xFFD4C8B8);

  /// Ánh xạ domain PaperColor sang Flutter Color hiển thị trên giao diện.
  static Color colorForPaper(PaperColor paperColor) {
    switch (paperColor) {
      case PaperColor.pink:
        return pink;
      case PaperColor.butter:
        return butter;
      case PaperColor.sage:
        return sage;
      case PaperColor.blue:
        return blue;
      case PaperColor.lilac:
        return lilac;
    }
  }

  /// Nhãn hiển thị tiếng Việt của 5 loại giấy pastel.
  static String labelForPaper(PaperColor paperColor) {
    switch (paperColor) {
      case PaperColor.pink:
        return 'Hồng pastel';
      case PaperColor.butter:
        return 'Vàng bơ';
      case PaperColor.sage:
        return 'Xanh xô thơm';
      case PaperColor.blue:
        return 'Xanh da trời';
      case PaperColor.lilac:
        return 'Tím đinh hương';
    }
  }
}
