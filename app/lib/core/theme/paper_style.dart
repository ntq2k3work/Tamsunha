/// Kiểu đính kèm của tờ giấy lên bề mặt tường.
enum PaperAttachmentType {
  none,
  tape, // Băng dính washitape mờ dán cạnh trên
  pin,  // Ghim tròn pastel/chibi
}

/// Tính toán các thuộc tính hiển thị mang tính tất định (deterministic) từ style_seed.
/// Tuân thủ contract: paper_color do người viết chọn và backend lưu riêng;
/// style_seed CHỈ quyết định attachment/rotation/angle vật lý.
class PaperDeterministicStyle {
  final int seed;
  final PaperAttachmentType attachmentType;
  final double rotationDeg;
  final double attachmentAngleDeg;

  const PaperDeterministicStyle({
    required this.seed,
    required this.attachmentType,
    required this.rotationDeg,
    required this.attachmentAngleDeg,
  });

  /// Sinh kiểu hiển thị tất định từ một giá trị seed nguyên.
  factory PaperDeterministicStyle.fromSeed(int seed) {
    final h1 = _mix(seed, 1);
    final h2 = _mix(seed, 2);
    final h3 = _mix(seed, 3);

    // 2 loại ghim/băng dính phân bổ đồng đều
    final attachment = (h1 % 2 == 0)
        ? PaperAttachmentType.tape
        : PaperAttachmentType.pin;

    // Góc xoay giấy trong khoảng [-5.0, 5.0] độ theo spec
    final rotation = ((h2 % 1001) / 100.0) - 5.0;

    // Góc nghiêng nhẹ của băng dính [-4.0, 4.0] độ
    final attachmentAngle = ((h3 % 801) / 100.0) - 4.0;

    return PaperDeterministicStyle(
      seed: seed,
      attachmentType: attachment,
      rotationDeg: rotation,
      attachmentAngleDeg: attachmentAngle,
    );
  }

  /// Hàm băm nguyên số 32-bit tất định, mask 32-bit sau mỗi phép nhân để tránh overflow âm
  static int _mix(int seed, int stream) {
    int h = (seed ^ (stream * 0x45d9f3b)) & 0xFFFFFFFF;
    h = (((h >> 16) ^ h) * 0x45d9f3b) & 0xFFFFFFFF;
    h = (((h >> 16) ^ h) * 0x45d9f3b) & 0xFFFFFFFF;
    // Mask 31-bit để luôn thu được số nguyên dương an toàn cho modulo
    h = ((h >> 16) ^ h) & 0x7FFFFFFF;
    return h;
  }
}
