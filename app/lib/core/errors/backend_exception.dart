final class BackendException implements Exception {
  const BackendException({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;

  factory BackendException.fromEnvelope(Map<String, Object?> error) {
    final code = error['code'] is String ? error['code']! as String : 'INTERNAL_ERROR';
    final retryable = error['retryable'] == true;
    return BackendException(
      code: code,
      retryable: retryable,
      message: _messageFor(code),
    );
  }

  factory BackendException.unavailable() => const BackendException(
        code: 'BACKEND_UNAVAILABLE',
        message: 'Chưa kết nối được dịch vụ. Hãy thử lại khi có mạng.',
        retryable: true,
      );

  factory BackendException.notConfigured() => const BackendException(
        code: 'BACKEND_NOT_CONFIGURED',
        message: 'Bản chính thức chưa được cấu hình. Bạn vẫn có thể xem bản thử cục bộ.',
      );

  static String _messageFor(String code) => switch (code) {
        'UNAUTHENTICATED' => 'Phiên đăng nhập đã kết thúc. Hãy đăng nhập lại.',
        'NOT_ELIGIBLE' => 'Hãy hoàn tất xác nhận tuổi và các điều khoản trước khi tiếp tục.',
        'AGE_RESTRICTED' => 'Tường Nhỏ chỉ dành cho người từ đủ 18 tuổi.',
        'CONSENT_REQUIRED' => 'Hãy đọc và đồng ý với các mục bắt buộc để tiếp tục.',
        'POLICY_VERSION_MISMATCH' => 'Điều khoản vừa được cập nhật. Hãy tải lại và xem phiên bản mới.',
        'SUSPENDED' => 'Tài khoản hiện không thể sử dụng chức năng này.',
        'INVALID_INPUT' => 'Thông tin chưa hợp lệ. Hãy kiểm tra lại.',
        'INVALID_VIEWPORT' => 'Khu vực đang xem quá rộng. Hãy phóng to thêm một chút.',
        'DAILY_LIMIT' => 'Hôm nay bạn đã dán một tờ giấy rồi. Ngày mai mình viết tiếp nhé.',
        'SLOT_OCCUPIED' => 'Vị trí này vừa có một tờ giấy khác.',
        'NOTE_NOT_FOUND' => 'Tờ giấy này không còn ở đây.',
        'EDIT_WINDOW_CLOSED' || 'EDIT_WINDOW_EXPIRED' =>
          'Đã hết thời gian có thể sửa tờ giấy này.',
        'NOTE_ALREADY_INTERACTED' =>
          'Tờ giấy đã có người gửi lời động viên hoặc bắt đầu trò chuyện nên không thể sửa nữa.',
        'CONTENT_REJECTED' => 'Nội dung chưa phù hợp với quy tắc cộng đồng.',
        'NEEDS_REVIEW' => 'Tờ giấy đang chờ được kiểm tra trước khi xuất hiện trên tường.',
        'ALREADY_ENCOURAGED' => 'Bạn đã gửi lời động viên cho tờ giấy này rồi.',
        'CHAT_DISABLED' => 'Người viết đã tắt nhận tin nhắn cho tờ giấy này.',
        'MESSAGE_LIMIT_REACHED' => 'Bạn đã gửi đủ 3 tin. Hãy chờ người kia trả lời nhé.',
        'BLOCKED' => 'Không thể thực hiện tương tác này.',
        'CLOSED' => 'Cuộc trò chuyện này đã được đóng.',
        'NOT_PARTICIPANT' => 'Không tìm thấy cuộc trò chuyện này.',
        'RATE_LIMITED' => 'Bạn thao tác hơi nhanh. Hãy đợi một chút rồi thử lại.',
        'IDEMPOTENCY_CONFLICT' => 'Yêu cầu này đã được dùng cho một thao tác khác.',
        'NETWORK_ERROR' || 'BACKEND_UNAVAILABLE' =>
          'Chưa kết nối được dịch vụ. Dữ liệu chưa được xác nhận; hãy thử lại.',
        'OTP_INVALID_OR_EXPIRED' => 'Mã xác nhận không đúng hoặc đã hết hạn.',
        'OTP_RATE_LIMITED' => 'Bạn vừa yêu cầu mã. Hãy chờ một chút rồi thử lại.',
        _ => 'Đã có lỗi xảy ra. Hãy thử lại sau.',
      };

  @override
  String toString() => message;
}

Map<String, Object?> requireRpcData(Object? response) {
  if (response is! Map) throw BackendException.unavailable();
  final envelope = Map<String, Object?>.from(response);
  final error = envelope['error'];
  if (error is Map) {
    throw BackendException.fromEnvelope(Map<String, Object?>.from(error));
  }
  final data = envelope['data'];
  if (data is! Map) throw BackendException.unavailable();
  return Map<String, Object?>.from(data);
}
