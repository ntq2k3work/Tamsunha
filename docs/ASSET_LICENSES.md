# ASSET LICENSES & PROVENANCE — TƯỜNG NHỎ

**Milestone:** M0-2  
**Cập nhật lần cuối:** 2026-10-23  
**Trạng thái:** Tự tạo nguyên bản (Native Vector-Only / No Third-Party Assets)

---

## 1. Tuyên bố bản quyền & Nguồn gốc đồ họa

Toàn bộ tài nguyên đồ họa hiện tại của dự án **Tường Nhỏ** được tạo bằng mã nguồn Flutter thuần (Vector Painting via `CustomPainter` & Flutter Framework Canvas API) do đội ngũ dự án trực tiếp lập trình, cụ thể:

| Thành phần | Cơ chế hiển thị | Nguồn gốc / Giấy phép | Tệp mã nguồn |
|---|---|---|---|
| **5 màu giấy pastel** | Định nghĩa mã màu CSS/Hex token (`pink`, `butter`, `sage`, `blue`, `lilac`) | Tự thiết kế theo spec | `app/lib/core/theme/app_colors.dart` |
| **Băng dính Washitape** | Đường Path vector răng cưa mô phỏng xé giấy thủ công | Tự vẽ (`TapePainter`) | `app/lib/core/widgets/paper_painters.dart` |
| **Ghim tròn Chibi (Pushpin)** | Vector hình học (Shadow + Circle + Highlight) | Tự vẽ (`PinPainter`) | `app/lib/core/widgets/paper_painters.dart` |
| **Vân giấy hạt liền mạch (Seamless Texture)** | Thuật toán sinh hạt và sợi giấy vi mô tĩnh theo lưới modulo | Tự lập trình (`SeamlessPaperPatternPainter`) | `app/lib/core/widgets/paper_painters.dart` |
| **Bộ biểu tượng (Icons)** | Material Icons tích hợp sẵn trong Flutter SDK | Apache 2.0 (Google Material Icons) | Thư viện chuẩn `flutter/material.dart` |
| **Phông chữ (Typography)** | Phông chữ hệ thống mặc định của thiết bị (Roboto trên Android, San Francisco trên iOS) | Bản quyền hệ điều hành thiết bị | Thư viện chuẩn `flutter/material.dart` |

---

## 2. Rà soát tài nguyên bên thứ ba (Third-party Assets)

* **Ảnh Raster (PNG / JPEG / WebP)**: **0 tệp**. Không sử dụng hình ảnh raster nhị phân dung lượng lớn nhằm đảm bảo không méo ở các tỷ lệ màn hình và giảm kích thước cài đặt.
* **Tệp âm thanh / video**: **0 tệp**.
* **Phông chữ tùy chỉnh (Custom Fonts)**: **Chưa cài đặt**. Chưa tích hợp phông chữ ngoài; tuân thủ nguyên tắc không thêm package bên thứ ba trong Milestone M0.
* **Shader nhị phân bên ngoài**: **Chưa sử dụng**.

---

## 3. Quy tắc bổ sung asset trong các Milestone tiếp theo

1. Mọi hình ảnh raster hoặc vector (SVG) được nhập vào `app/assets/` phải có chứng nhận giấy phép hợp lệ (ví dụ: CC0, MIT, SIL Open Font License, hoặc tài sản có bản quyền thuộc sở hữu của chủ dự án).
2. Tuyệt đối không sử dụng tài nguyên tìm kiếm ngẫu nhiên trên mạng mà không rõ tác quyền.
3. Mọi asset mới phải được ghi nhận đầy đủ vào tệp `docs/ASSET_LICENSES.md` này kèm đường dẫn, tác giả, và tóm tắt điều khoản giấy phép trước khi đưa vào codebase chính thức.
