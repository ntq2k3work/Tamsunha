# Asset Pipeline — Tường Nhỏ (M0-2)

Thư mục lưu trữ assets tĩnh của ứng dụng Tường Nhỏ.

## Chiến lược dựng hình (Vector-First Strategy)
Để tối ưu hiệu năng trên thiết bị di động, tránh hiện tượng méo vỡ ở các tỷ lệ màn hình và giảm dung lượng gói cài đặt về mức tối thiểu (0 KB binary bloat), toàn bộ các thành phần đồ họa cốt lõi trong Milestone M0-2 được dựng bằng **Vector Painting Flutter thuần** (`CustomPainter`):
- **5 màu giấy pastel**: Định nghĩa trong `AppColors` (`app/lib/core/theme/app_colors.dart`).
- **2 kiểu đính kèm (Băng dính washitape và Ghim tròn)**: Dựng vector trong `TapePainter` và `PinPainter` (`app/lib/core/widgets/paper_painters.dart`).
- **Nền giấy hạt lặp liền mạch (Seamless Paper Texture)**: Sinh hạt và sợi vi mô tĩnh bằng `SeamlessPaperPatternPainter` (`app/lib/core/widgets/paper_painters.dart`).
- **Biến thiên tất định**: Tính toán theo `style_seed` qua `PaperDeterministicStyle` (`app/lib/core/theme/paper_style.dart`).

Không sử dụng các tệp PNG/JPEG kích thước lớn trong giai đoạn này.
