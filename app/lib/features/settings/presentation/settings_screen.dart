import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/paper_sheet.dart';

/// Màn hình Cài đặt & Quyền riêng tư (S11).
///
/// Hỗ trợ các tùy chọn trải nghiệm (Giảm chuyển động), xem lại các quy tắc/chính sách,
/// và quản lý tài khoản (Đăng xuất, Yêu cầu xóa tài khoản theo chính sách bảo mật).
class SettingsScreen extends StatefulWidget {
  /// Thông báo đẩy có khả dụng trên thiết bị / bản cài đặt hay không.
  final bool notificationsAvailable;

  /// Trạng thái bật/tắt nhận thông báo (Notifications opt-in).
  final bool notificationsEnabled;

  /// Trạng thái bật/tắt giảm chuyển động (Reduce motion).
  final bool reduceMotionEnabled;

  /// Email tài khoản đã đăng nhập (nếu có).
  final String? userEmail;

  /// Người dùng có vai trò kiểm duyệt viên hay không.
  final bool isModerator;

  /// Đang thực hiện tác vụ tài khoản (đăng xuất hoặc xóa tài khoản).
  final bool isSubmitting;

  /// Thông báo lỗi từ server nếu có.
  final String? errorMessage;

  /// Callback chuyển đổi trạng thái nhận thông báo.
  final Future<void> Function(bool)? onToggleNotifications;

  /// Callback chuyển đổi chế độ giảm chuyển động.
  final ValueChanged<bool>? onToggleReduceMotion;

  /// Callback mở Bảng quản trị & Kiểm duyệt viên (Moderator Console).
  final VoidCallback? onOpenModerator;

  /// Callback đăng xuất phiên làm việc.
  final Future<void> Function()? onSignOut;

  /// Callback yêu cầu xóa tài khoản.
  final Future<void> Function()? onRequestAccountDeletion;

  const SettingsScreen({
    super.key,
    this.notificationsAvailable = true,
    this.notificationsEnabled = false,
    this.reduceMotionEnabled = false,
    this.userEmail,
    this.isModerator = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.onToggleNotifications,
    this.onToggleReduceMotion,
    this.onOpenModerator,
    this.onSignOut,
    this.onRequestAccountDeletion,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isActionSubmitting = false;

  bool get _effectiveSubmitting => widget.isSubmitting || _isActionSubmitting;

  void _showPolicyDialog(BuildContext context, String title, String content) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperSurface,
        title: Text(title, style: AppTypography.titleMedium),
        content: SingleChildScrollView(
          child: Text(content, style: AppTypography.bodySmall),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng', style: AppTypography.caption),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    bool isPending = false;
    String? dialogError;

    showDialog<void>(
      context: context,
      barrierDismissible: !isPending && !_effectiveSubmitting,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isBusy = isPending || _effectiveSubmitting;
          return AlertDialog(
            backgroundColor: AppColors.paperSurface,
            title: const Text('Xác nhận đăng xuất', style: AppTypography.titleMedium),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bạn sẽ cần nhập mã xác thực email OTP để đăng nhập lại trong lần tiếp theo.',
                  style: AppTypography.bodySmall,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    dialogError!,
                    style: AppTypography.caption.copyWith(color: AppColors.pink),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Hủy', style: AppTypography.caption),
              ),
              TextButton(
                onPressed: isBusy || widget.onSignOut == null
                    ? null
                    : () async {
                        setDialogState(() {
                          isPending = true;
                          dialogError = null;
                        });
                        setState(() => _isActionSubmitting = true);
                        try {
                          await widget.onSignOut!();
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              isPending = false;
                              dialogError = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isActionSubmitting = false);
                          }
                        }
                      },
                child: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.pink),
                        ),
                      )
                    : Text(
                        'Đăng xuất',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.pink,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    bool isPending = false;
    String? dialogError;

    showDialog<void>(
      context: context,
      barrierDismissible: !isPending && !_effectiveSubmitting,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isBusy = isPending || _effectiveSubmitting;
          return AlertDialog(
            backgroundColor: AppColors.paperSurface,
            title: const Text('Yêu cầu xóa tài khoản', style: AppTypography.titleMedium),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Thao tác này sẽ gửi yêu cầu xóa tài khoản lên hệ thống và tạm khóa quyền truy cập cũng như nội dung của bạn trong thời gian chờ xử lý. Yêu cầu xóa dữ liệu sẽ được thực thi theo chính sách lưu trữ và quy định hiện hành.',
                  style: AppTypography.bodySmall,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    dialogError!,
                    style: AppTypography.caption.copyWith(color: AppColors.pink),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Hủy', style: AppTypography.caption),
              ),
              TextButton(
                onPressed: isBusy || widget.onRequestAccountDeletion == null
                    ? null
                    : () async {
                        setDialogState(() {
                          isPending = true;
                          dialogError = null;
                        });
                        setState(() => _isActionSubmitting = true);
                        try {
                          await widget.onRequestAccountDeletion!();
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              isPending = false;
                              dialogError = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isActionSubmitting = false);
                          }
                        }
                      },
                child: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.pink),
                        ),
                      )
                    : Text(
                        'Gửi yêu cầu xóa',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.pink,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Cài đặt & Riêng tư'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Thông báo lỗi chung nếu có
            if (widget.errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.pink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.paperBorder, width: 1),
                ),
                child: Text(
                  widget.errorMessage!,
                  style: AppTypography.caption,
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // Nhóm Cài đặt trải nghiệm
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Trải nghiệm', style: AppTypography.titleMedium),
            ),
            PaperSheet(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.notifications_outlined,
                    title: 'Thông báo',
                    subtitle: widget.notificationsAvailable
                        ? 'Hộp thư trong ứng dụng vẫn luôn hoạt động nếu quyền thông báo thiết bị bị từ chối'
                        : 'Chưa cấu hình thông báo đẩy; hộp thư trong ứng dụng vẫn luôn hoạt động',
                    trailing: Switch.adaptive(
                      value: widget.notificationsAvailable && widget.notificationsEnabled,
                      activeColor: AppColors.ink,
                      onChanged: !widget.notificationsAvailable ||
                              _effectiveSubmitting ||
                              widget.onToggleNotifications == null
                          ? null
                          : (value) => unawaited(widget.onToggleNotifications!(value)),
                    ),
                  ),
                  const Divider(color: AppColors.paperBorder, height: 1),
                  _SettingsTile(
                    icon: Icons.motion_photos_off_outlined,
                    title: 'Giảm chuyển động',
                    subtitle: 'Hạn chế hiệu ứng bay và rung động của giấy (Reduced motion)',
                    trailing: Switch.adaptive(
                      value: widget.reduceMotionEnabled,
                      activeColor: AppColors.ink,
                      onChanged: _effectiveSubmitting ? null : widget.onToggleReduceMotion,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Nhóm Quy tắc & Bảo mật
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Quy tắc & An toàn', style: AppTypography.titleMedium),
            ),
            PaperSheet(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.eighteen_up_rating_outlined,
                    title: 'Cam kết độ tuổi 18+',
                    subtitle: 'Ứng dụng chỉ dành cho người trưởng thành',
                    onTap: () => _showPolicyDialog(
                      context,
                      'Cam kết độ tuổi 18+',
                      'Tường Nhỏ là không gian nhật ký và chia sẻ tâm sự chỉ dành riêng cho người từ đủ 18 tuổi trở lên. Chúng mình không cung cấp dịch vụ cho trẻ em và vị thành niên nhằm bảo vệ người dùng và đảm bảo sự thấu cảm chín chắn.',
                    ),
                  ),
                  const Divider(color: AppColors.paperBorder, height: 1),
                  _SettingsTile(
                    icon: Icons.policy_outlined,
                    title: 'Quy tắc cộng đồng',
                    subtitle: 'Tôn trọng và giữ gìn sự tĩnh lặng',
                    onTap: () => _showPolicyDialog(
                      context,
                      'Quy tắc cộng đồng',
                      '1. Một tờ giấy mỗi ngày (giờ Việt Nam).\n'
                      '2. Không quấy rối, thù ghét, đăng tải nội dung khiêu dâm hoặc thông tin cá nhân của người khác.\n'
                      '3. 5 câu động viên định sẵn, không dùng nút Like hay so sánh số đông.\n'
                      '4. Trò chuyện tối đa 3 tin nhắn liên tiếp khi đối phương chưa phản hồi.',
                    ),
                  ),
                  const Divider(color: AppColors.paperBorder, height: 1),
                  _SettingsTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Chính sách riêng tư',
                    subtitle: 'Ẩn danh trước người khác, không ẩn danh với nhà cung cấp dịch vụ',
                    onTap: () => _showPolicyDialog(
                      context,
                      'Chính sách riêng tư',
                      'Bạn hoàn toàn ẩn danh trước các thành viên khác: không có hồ sơ, ảnh đại diện, danh sách theo dõi hay nickname công khai.\n\n'
                      'Tuy nhiên, bạn không ẩn danh đối với nhà cung cấp dịch vụ và pháp luật. Nhật ký và tin nhắn được lưu trữ tuân thủ các quy định hiện hành nhằm bảo vệ an toàn cộng đồng.',
                    ),
                  ),
                  const Divider(color: AppColors.paperBorder, height: 1),
                  _SettingsTile(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Lưu ý hỗ trợ khẩn cấp',
                    subtitle: 'Tường Nhỏ không phải dịch vụ can thiệp y tế hay khủng hoảng',
                    onTap: () => _showPolicyDialog(
                      context,
                      'Lưu ý an toàn sức khỏe',
                      'Tường Nhỏ là một không gian nhật ký cá nhân và tâm sự tĩnh lặng, KHÔNG thay thế cho dịch vụ y tế, tư vấn chuyên khoa hay chăm sóc sức khỏe tâm thần khẩn cấp.\n\n'
                      'Nếu bạn hoặc người thân đang trải qua khủng hoảng tâm lý nghiêm trọng hoặc có tình huống khẩn cấp, xin vui lòng liên hệ ngay với các dịch vụ cấp cứu y tế, cơ quan y tế có thẩm quyền tại địa phương hoặc người thân đáng tin cậy để được hỗ trợ kịp thời.',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Nhóm Tài khoản
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Tài khoản', style: AppTypography.titleMedium),
            ),
            PaperSheet(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.mail_outline_rounded,
                    title: 'Email đăng nhập',
                    subtitle: widget.userEmail ?? 'Chưa kết nối tài khoản chính thức',
                  ),
                  const Divider(color: AppColors.paperBorder, height: 1),
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    title: 'Đăng xuất',
                    subtitle: widget.userEmail != null ? 'Thoát phiên làm việc hiện tại' : 'Chưa có phiên đăng nhập',
                    onTap: widget.userEmail != null && !_effectiveSubmitting ? () => _confirmSignOut(context) : null,
                  ),
                  const Divider(color: AppColors.paperBorder, height: 1),
                  _SettingsTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'Yêu cầu xóa tài khoản',
                    subtitle: 'Gửi yêu cầu xóa và khóa nội dung theo chính sách lưu trữ',
                    isDestructive: true,
                    onTap: !_effectiveSubmitting ? () => _confirmDeleteAccount(context) : null,
                  ),
                ],
              ),
            ),

            // Nhóm Quản trị viên (Chỉ hiển thị khi isModerator == true)
            if (widget.isModerator) ...[
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Quản trị & Kiểm duyệt', style: AppTypography.titleMedium),
              ),
              PaperSheet(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Bảng quản trị an toàn',
                      subtitle: 'Kiểm duyệt báo cáo, duyệt giấy và xử lý yêu cầu xóa',
                      onTap: _effectiveSubmitting ? null : widget.onOpenModerator,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDestructive ? AppColors.pink : AppColors.ink,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelLarge.copyWith(
                      color: isDestructive ? AppColors.pink : AppColors.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTypography.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppColors.inkSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
