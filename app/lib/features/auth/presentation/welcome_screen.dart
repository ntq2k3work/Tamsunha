import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/paper_button.dart';
import '../../../core/widgets/paper_sheet.dart';

/// Giai đoạn xác thực đăng nhập qua Email OTP.
enum AuthStep {
  /// Bước 1: Nhập email để nhận mã OTP.
  emailInput,

  /// Bước 2: Nhập mã 6 chữ số đã gửi qua email.
  otpInput,
}

/// Màn hình Chào đón / Đăng nhập Email OTP (S01).
///
/// Hỗ trợ cả hai bước xác thực không mật khẩu (Passwordless OTP):
/// 1. Nhập email cá nhân.
/// 2. Nhập mã OTP 6 số với bộ đếm thời gian gửi lại (Cooldown Timer).
///
/// Cung cấp hợp đồng callback cho Codex kết nối API auth,
/// đồng thời có trạng thái cục bộ tự hoạt động khi chạy độc lập.
class WelcomeScreen extends StatefulWidget {
  /// Giai đoạn ban đầu khi mở màn hình.
  final AuthStep initialStep;

  /// Email điền sẵn (nếu có từ phiên trước).
  final String? initialEmail;

  /// Đang xử lý yêu cầu mạng (gửi OTP hoặc xác thực mã).
  final bool isSubmitting;

  /// Thông báo lỗi từ server (nếu mã sai hoặc mạng gián đoạn).
  final String? errorMessage;

  /// Số giây chờ giữa các lần yêu cầu gửi lại mã (mặc định 60 giây).
  final int resendCooldownSeconds;

  /// Callback khi người dùng nhấn gửi mã OTP cho email.
  final Future<void> Function(String email)? onSendEmailOtp;

  /// Callback khi người dùng nhập đủ và xác nhận mã OTP.
  final Future<void> Function(String email, String otp)? onVerifyOtp;

  /// Callback khi người dùng yêu cầu gửi lại mã OTP.
  final Future<void> Function(String email)? onResendOtp;

  /// Callback mở bản thử nghiệm ngoại tuyến (M1 POC).
  final VoidCallback? onOpenOfflineDemo;

  const WelcomeScreen({
    super.key,
    this.initialStep = AuthStep.emailInput,
    this.initialEmail,
    this.isSubmitting = false,
    this.errorMessage,
    this.resendCooldownSeconds = 60,
    this.onSendEmailOtp,
    this.onVerifyOtp,
    this.onResendOtp,
    this.onOpenOfflineDemo,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late AuthStep _currentStep;
  late final TextEditingController _emailController;
  late final TextEditingController _otpController;

  Timer? _cooldownTimer;
  int _secondsRemaining = 0;
  String? _localError;
  bool _isPending = false;

  bool get _effectiveSubmitting => widget.isSubmitting || _isPending;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep;
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    _otpController = TextEditingController();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsRemaining = widget.resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    return trimmed.contains('@') && trimmed.contains('.') && trimmed.length >= 5;
  }

  Future<void> _handleSendEmail() async {
    if (_effectiveSubmitting) return;

    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _localError = 'Vui lòng nhập địa chỉ email hợp lệ');
      return;
    }

    if (widget.onSendEmailOtp == null) {
      setState(() => _localError =
          'Dịch vụ gửi mã OTP chưa được kết nối. Vui lòng sử dụng nút "Xem bản thử cục bộ" bên dưới để trải nghiệm.');
      return;
    }

    setState(() {
      _localError = null;
      _isPending = true;
    });

    try {
      await widget.onSendEmailOtp!(email);
      if (mounted) {
        setState(() {
          _isPending = false;
          _currentStep = AuthStep.otpInput;
        });
        _startCooldown();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPending = false;
          _localError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    if (_effectiveSubmitting) return;

    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      setState(() => _localError = 'Mã xác thực gồm 6 chữ số');
      return;
    }

    if (widget.onVerifyOtp == null) {
      setState(() => _localError =
          'Dịch vụ xác thực chưa được kết nối. Không thể xác nhận mã trong bản xem trước giao diện.');
      return;
    }

    setState(() {
      _localError = null;
      _isPending = true;
    });

    try {
      await widget.onVerifyOtp!(_emailController.text.trim(), otp);
      if (mounted) {
        setState(() => _isPending = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPending = false;
          _localError = e.toString().replaceFirst('Exception: ', '');
          // Giữ nguyên mã OTP đã nhập trên giao diện khi thất bại, không xóa trường nhập
        });
      }
    }
  }

  Future<void> _handleResend() async {
    if (_secondsRemaining > 0 || _effectiveSubmitting) return;

    final email = _emailController.text.trim();
    if (widget.onResendOtp == null) {
      setState(() => _localError =
          'Dịch vụ gửi lại mã chưa được kết nối trong bản xem trước này.');
      return;
    }

    setState(() {
      _localError = null;
      _isPending = true;
    });

    try {
      await widget.onResendOtp!(email);
      if (mounted) {
        setState(() => _isPending = false);
        _startCooldown();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPending = false;
          _localError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _handleChangeEmail() {
    if (_effectiveSubmitting) return;
    _cooldownTimer?.cancel();
    _otpController.clear();
    setState(() {
      _currentStep = AuthStep.emailInput;
      _localError = null;
      _secondsRemaining = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveError = widget.errorMessage ?? _localError;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: PaperSheet(
                showTape: true,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Biểu tượng ứng dụng
                    const Icon(
                      Icons.favorite_border_rounded,
                      size: 40,
                      color: AppColors.ink,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tường Nhỏ',
                      textAlign: TextAlign.center,
                      style: AppTypography.displayLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Không gian viết nhật ký tĩnh lặng dành cho người trên 18 tuổi. Mỗi ngày một tờ giấy nhỏ được dán lên bức tường chung.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: 20),

                    // Thẻ cam kết bảo mật & ẩn danh (§4.1)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.paperBorder, width: 1),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, size: 20, color: AppColors.inkSecondary),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ẩn danh trước người dùng khác (không ẩn danh với nhà cung cấp dịch vụ). Không hồ sơ công khai, không lượt thích hay theo dõi.',
                              style: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Thông báo lỗi nếu có
                    if (effectiveError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.pink,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.paperBorder, width: 1),
                        ),
                        child: Text(
                          effectiveError,
                          style: AppTypography.caption.copyWith(color: AppColors.ink),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Nội dung theo bước xác thực
                    if (_currentStep == AuthStep.emailInput)
                      _buildEmailStep()
                    else
                      _buildOtpStep(),

                    // Lối vào bản thử nghiệm ngoại tuyến (M1 POC)
                    const SizedBox(height: 20),
                    const Divider(color: AppColors.paperBorder, height: 1),
                    const SizedBox(height: 16),
                    PaperButton(
                      label: 'Xem bản thử cục bộ',
                      isPrimary: false,
                      icon: Icons.grid_view_rounded,
                      onPressed: widget.onOpenOfflineDemo,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bản thử nghiệm ngoại tuyến (M1): Các tờ giấy chỉ lưu tạm trên thiết bị này, không được chia sẻ hay xuất bản lên bức tường cộng đồng.',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Giao diện Bước 1: Nhập email
  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Email đăng nhập',
          style: AppTypography.labelLarge,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          autocorrect: false,
          style: AppTypography.bodyMedium,
          decoration: InputDecoration(
            hintText: 'ban@vidu.com',
            hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.inkSecondary),
            filled: true,
            fillColor: AppColors.canvas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.inkSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.paperBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.paperBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _handleSendEmail(),
        ),
        const SizedBox(height: 16),
        PaperButton(
          label: _effectiveSubmitting
              ? 'Đang gửi mã...'
              : widget.onSendEmailOtp != null
                  ? 'Nhận mã OTP qua Email'
                  : 'Tiếp tục với Email (Chờ kết nối M2)',
          icon: Icons.send_rounded,
          onPressed: (_effectiveSubmitting || widget.onSendEmailOtp == null)
              ? null
              : _handleSendEmail,
        ),
      ],
    );
  }

  /// Giao diện Bước 2: Nhập mã 6 chữ số
  Widget _buildOtpStep() {
    final email = _emailController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nhập mã xác thực',
          style: AppTypography.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Mã 6 chữ số đã được gửi tới $email',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: AppTypography.displayLarge.copyWith(
            letterSpacing: 10,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: AppTypography.displayLarge.copyWith(
              letterSpacing: 10,
              color: AppColors.inkSecondary.withValues(alpha: 0.4),
            ),
            filled: true,
            fillColor: AppColors.canvas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.paperBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.paperBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _handleVerifyOtp(),
        ),
        const SizedBox(height: 16),
        PaperButton(
          label: _effectiveSubmitting
              ? 'Đang xác thực...'
              : widget.onVerifyOtp != null
                  ? 'Xác nhận đăng nhập'
                  : 'Xác nhận đăng nhập (Chờ kết nối)',
          icon: Icons.check_rounded,
          onPressed: (_effectiveSubmitting || widget.onVerifyOtp == null)
              ? null
              : _handleVerifyOtp,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _effectiveSubmitting ? null : _handleChangeEmail,
              child: const Text(
                'Đổi email khác',
                style: AppTypography.caption,
              ),
            ),
            TextButton(
              onPressed: _secondsRemaining > 0 || _effectiveSubmitting || widget.onResendOtp == null
                  ? null
                  : _handleResend,
              child: Text(
                _secondsRemaining > 0
                    ? 'Gửi lại sau (${_secondsRemaining}s)'
                    : widget.onResendOtp != null
                        ? 'Gửi lại mã'
                        : 'Gửi lại mã (Chưa khả dụng)',
                style: AppTypography.caption.copyWith(
                  color: (_secondsRemaining > 0 || widget.onResendOtp == null || _effectiveSubmitting)
                      ? AppColors.inkSecondary
                      : AppColors.ink,
                  fontWeight: (_secondsRemaining > 0 || widget.onResendOtp == null || _effectiveSubmitting)
                      ? FontWeight.normal
                      : FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
