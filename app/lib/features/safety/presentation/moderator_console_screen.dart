import 'package:flutter/material.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/chibi_empty_state.dart';
import '../../../core/widgets/paper_sheet.dart';

/// Dữ liệu một mục trong hàng đợi Báo cáo (Report Queue — S12 / ADM).
/// Tuyệt đối KHÔNG chứa ID cá nhân, email hay thông tin định danh của người báo cáo hay người bị báo cáo.
class ModeratorReportItem {
  final String reportId;
  final String targetType; // 'note' | 'conversation' | 'message' | 'user'
  final String targetId; // empty for user reports; never rendered in the UI
  final String reason;
  final String? detail;
  final String? contentSnippet;
  final DateTime reportedAt;
  final String status; // 'pending' | 'resolved' | 'dismissed'

  const ModeratorReportItem({
    required this.reportId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.detail,
    this.contentSnippet,
    required this.reportedAt,
    this.status = 'pending',
  });
}

/// Dữ liệu một nội dung trong hàng đợi kiểm duyệt (Moderation Queue — §4.2 / ADM).
/// Hỗ trợ cả note và message. Tuyệt đối KHÔNG chứa user ID hay email.
class ModeratorContentReviewItem {
  final String targetType; // 'note' | 'message'
  final String targetId;
  final String content;
  final PaperColor? paperColor; // Nullable đối với message hoặc note không màu
  final String reviewReason;
  final DateTime submittedAt;
  final String status; // 'pending_review' | 'published' | 'hidden'

  const ModeratorContentReviewItem({
    String? targetType,
    String? targetId,
    String? noteId,
    required this.content,
    this.paperColor,
    required this.reviewReason,
    required this.submittedAt,
    this.status = 'pending_review',
  })  : targetType = targetType ?? 'note',
        targetId = targetId ?? noteId ?? '';

  String get noteId => targetId;
  bool get isNote => targetType == 'note';
  bool get isMessage => targetType == 'message';
}

typedef ModeratorNoteReviewItem = ModeratorContentReviewItem;

/// Dữ liệu một yêu cầu xóa tài khoản trong hàng đợi (Deletion Queue — §1054 / ADM).
/// Chỉ sử dụng mã tham chiếu ẩn danh (opaque ref), không phơi bày email hay ID người dùng.
class ModeratorDeletionItem {
  final String requestId;
  final String opaqueAccountRef;
  final DateTime requestedAt;
  final String status; // 'pending_processing' | 'content_hidden' | 'completed'

  const ModeratorDeletionItem({
    required this.requestId,
    required this.opaqueAccountRef,
    required this.requestedAt,
    this.status = 'pending_processing',
  });
}

/// Màn hình Bảng quản trị & Kiểm duyệt an toàn (Moderator Console — S13 / ADM).
///
/// Hỗ trợ:
/// 1. 3 hàng đợi vận hành: Hàng đợi Báo cáo, Hàng đợi Duyệt nội dung, và Hàng đợi Xóa tài khoản.
/// 2. Hợp đồng dữ liệu rõ ràng, không tạo dữ liệu giả lập (No fabricated rows).
/// 3. Bảo vệ quyền riêng tư tuyệt đối: Không phơi bày email, nickname hay user ID.
/// 4. Mọi thao tác kiểm duyệt đều có Dialog xác nhận rõ ràng trước khi phát sinh callback.
/// 5. Phân quyền vai trò (Role Authorization) do Caller/Backend kiểm soát.
class ModeratorConsoleScreen extends StatefulWidget {
  final List<ModeratorReportItem>? reportQueue;
  final List<ModeratorContentReviewItem>? moderationQueue;
  final List<ModeratorDeletionItem>? deletionQueue;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onBack;

  /// Thao tác xử lý báo cáo: 'hide' | 'dismiss' | 'resolve' kèm lý do (tối đa 500 ký tự)
  final Future<void> Function(String reportId, String action, String reason)? onResolveReport;

  /// Thao tác duyệt nội dung (note hoặc message): 'approve' | 'reject' kèm lý do (tối đa 500 ký tự)
  final Future<void> Function(String targetType, String targetId, String action, String reason)? onModerateContent;

  /// Callback duyệt kiểm duyệt (tương thích cả onModerateNote và onModerateContent)
  final Function? onModerateNote;

  /// Thao tác xử lý yêu cầu xóa: 'start_processing' | 'hold' kèm lý do (tối đa 500 ký tự)
  final Future<void> Function(String requestId, String action, String reason)? onProcessDeletion;

  const ModeratorConsoleScreen({
    super.key,
    this.reportQueue,
    this.moderationQueue,
    this.deletionQueue,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
    this.onBack,
    this.onResolveReport,
    this.onModerateContent,
    this.onModerateNote,
    this.onProcessDeletion,
  });

  @override
  State<ModeratorConsoleScreen> createState() => _ModeratorConsoleScreenState();
}

class _ModeratorConsoleScreenState extends State<ModeratorConsoleScreen> {
  int _selectedQueueIndex = 0; // 0: Báo cáo, 1: Duyệt nội dung, 2: Xóa tài khoản

  bool get _hasModerationCallback =>
      widget.onModerateContent != null || widget.onModerateNote != null;

  Future<void> _handleModerate({
    required String targetType,
    required String targetId,
    required String action,
    required String reason,
  }) async {
    if (widget.onModerateContent != null) {
      await widget.onModerateContent!(targetType, targetId, action, reason);
    } else if (widget.onModerateNote != null) {
      final fn = widget.onModerateNote!;
      if (fn is Future<void> Function(String, String, String, String)) {
        await fn(targetType, targetId, action, reason);
      } else if (fn is Future<void> Function(String, String, String)) {
        await fn(targetId, action, reason);
      } else {
        final dynamic res = Function.apply(fn, [targetType, targetId, action, reason]);
        if (res is Future) await res;
      }
    }
  }

  static String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} giờ trước';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showActionWithReasonDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmLabel,
    required Future<void> Function(String reason) onConfirm,
    bool isDestructive = false,
  }) {
    final reasonController = TextEditingController();
    bool isSubmitting = false;
    String? dialogError;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final trimmedReason = reasonController.text.trim();
          final isValid = trimmedReason.isNotEmpty && trimmedReason.length <= 500;
          final canSubmit = isValid && !isSubmitting;

          return AlertDialog(
            backgroundColor: AppColors.paperSurface,
            title: Text(title, style: AppTypography.titleMedium),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(content, style: AppTypography.bodySmall),
                  const SizedBox(height: 16),
                  const Text(
                    'Lý do xử lý (bắt buộc):',
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonController,
                    enabled: !isSubmitting,
                    maxLength: 500,
                    maxLines: 3,
                    minLines: 2,
                    style: AppTypography.bodySmall,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Nhập lý do kiểm duyệt (tối đa 500 ký tự)...',
                      hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.inkSecondary),
                      filled: true,
                      fillColor: AppColors.canvas,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.paperBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.paperBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
                      ),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.pink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        dialogError!,
                        style: AppTypography.caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Hủy', style: AppTypography.caption),
              ),
              TextButton(
                onPressed: canSubmit
                    ? () async {
                        setDialogState(() {
                          isSubmitting = true;
                          dialogError = null;
                        });
                        try {
                          await onConfirm(trimmedReason);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          await widget.onRefresh?.call();
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              isSubmitting = false;
                              dialogError = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        }
                      }
                    : null,
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.ink),
                        ),
                      )
                    : Text(
                        confirmLabel,
                        style: AppTypography.caption.copyWith(
                          color: canSubmit
                              ? (isDestructive ? AppColors.pink : AppColors.ink)
                              : AppColors.inkSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ).then((_) => reasonController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final reportCount = widget.reportQueue?.length ?? 0;
    final moderationCount = widget.moderationQueue?.length ?? 0;
    final deletionCount = widget.deletionQueue?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bảng quản trị an toàn', style: AppTypography.titleMedium),
            Text('Khu vực dành cho kiểm duyệt viên', style: AppTypography.caption),
          ],
        ),
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: widget.onBack,
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh chuyển hàng đợi
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.paperSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.paperBorder, width: 1),
                ),
                child: Row(
                  children: [
                    _buildTabButton(0, 'Báo cáo', reportCount),
                    _buildTabButton(1, 'Duyệt nội dung', moderationCount),
                    _buildTabButton(2, 'Yêu cầu xóa', deletionCount),
                  ],
                ),
              ),
            ),

            // Thông báo lỗi nếu có
            if (widget.errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.pink,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.errorMessage!,
                        style: AppTypography.caption,
                      ),
                    ),
                  ],
                ),
              ),

            // Nội dung theo hàng đợi
            Expanded(
              child: widget.isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.inkSecondary),
                        ),
                      ),
                    )
                  : _buildSelectedQueueContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, int count) {
    final isSelected = _selectedQueueIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedQueueIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.tape : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count > 0 ? '$label ($count)' : label,
            style: isSelected ? AppTypography.labelLarge : AppTypography.bodySmall,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedQueueContent() {
    switch (_selectedQueueIndex) {
      case 0:
        return _buildReportQueue();
      case 1:
        return _buildModerationQueue();
      case 2:
        return _buildDeletionQueue();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Hàng đợi 0: Báo cáo vi phạm từ người dùng
  Widget _buildReportQueue() {
    final list = widget.reportQueue;

    if (list == null || list.isEmpty) {
      return const ChibiEmptyState(
        icon: Icons.shield_outlined,
        title: 'Hàng đợi báo cáo trống',
        description: 'Hiện không có nội dung nào bị người dùng báo cáo cần xử lý.',
      );
    }

    final content = ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final item = list[index];

        return PaperSheet(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.paperPink,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.targetType.toUpperCase(),
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatRelativeTime(item.reportedAt),
                    style: AppTypography.caption,
                  ),
                  const Spacer(),
                  Text(
                    'Lý do: ${item.reason}',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (item.contentSnippet != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.paperBorder, width: 0.5),
                  ),
                  child: Text(
                    '“${item.contentSnippet}”',
                    style: AppTypography.bodySmall,
                  ),
                ),
              if (item.detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Chi tiết người báo cáo: ${item.detail}',
                  style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 12),
              // Nút hành động kiểm duyệt
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onResolveReport == null
                        ? null
                        : () => _showActionWithReasonDialog(
                              context: context,
                              title: 'Bác bỏ báo cáo',
                              content: 'Báo cáo sẽ được đánh dấu là không vi phạm và đóng lại.',
                              confirmLabel: 'Bác bỏ',
                              onConfirm: (reason) =>
                                  widget.onResolveReport!(item.reportId, 'dismiss', reason),
                            ),
                    child: const Text('Bác bỏ', style: AppTypography.caption),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onResolveReport == null
                        ? null
                        : () => _showActionWithReasonDialog(
                              context: context,
                              title: 'Giải quyết báo cáo',
                              content: 'Đánh dấu báo cáo đã được xử lý thỏa đáng.',
                              confirmLabel: 'Giải quyết',
                              onConfirm: (reason) =>
                                  widget.onResolveReport!(item.reportId, 'resolve', reason),
                            ),
                    child: const Text('Giải quyết', style: AppTypography.caption),
                  ),
                  const SizedBox(width: 8),
                  if (item.targetType.toLowerCase() == 'user')
                    TextButton(
                      onPressed: widget.onResolveReport == null
                          ? null
                          : () => _showActionWithReasonDialog(
                                context: context,
                                title: 'Xác nhận tạm khóa tài khoản',
                                content:
                                    'Tài khoản bị báo cáo sẽ bị tạm khóa quyền truy cập dịch vụ và báo cáo này sẽ được đánh dấu đã giải quyết.',
                                confirmLabel: 'Tạm khóa tài khoản',
                                isDestructive: true,
                                onConfirm: (reason) =>
                                    widget.onResolveReport!(item.reportId, 'suspend_user', reason),
                              ),
                      child: Text(
                        'Tạm khóa tài khoản',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.pink,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: widget.onResolveReport == null
                          ? null
                          : () => _showActionWithReasonDialog(
                                context: context,
                                title: 'Xác nhận ẩn nội dung',
                                content: 'Nội dung này sẽ bị gỡ bỏ khỏi chế độ hiển thị công khai ngay lập tức.',
                                confirmLabel: 'Ẩn nội dung',
                                isDestructive: true,
                                onConfirm: (reason) =>
                                    widget.onResolveReport!(item.reportId, 'hide', reason),
                              ),
                      child: Text(
                        'Ẩn nội dung',
                        style: AppTypography.caption.copyWith(color: AppColors.pink, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );

    return widget.onRefresh != null
        ? RefreshIndicator(onRefresh: widget.onRefresh!, color: AppColors.ink, child: content)
        : content;
  }

  /// Hàng đợi 1: Duyệt nội dung (Note & Message) chờ phê duyệt
  Widget _buildModerationQueue() {
    final list = widget.moderationQueue;

    if (list == null || list.isEmpty) {
      return const ChibiEmptyState(
        icon: Icons.checklist_rounded,
        title: 'Hàng đợi kiểm duyệt trống',
        description:
            'Tất cả các tờ giấy và tin nhắn gửi lên đều đã được xử lý hoặc xuất bản tự động.',
      );
    }

    final content = ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final item = list[index];
        final isNote = item.isNote;

        return PaperSheet(
          paperColor: item.paperColor,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Badge hiển thị loại nội dung rõ ràng (Note hoặc Message)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isNote ? AppColors.paperButter : AppColors.paperBlue,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.paperBorder, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isNote ? Icons.description_outlined : Icons.chat_bubble_outline_rounded,
                          size: 13,
                          color: AppColors.ink,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isNote ? 'TỜ GIẤY' : 'TIN NHẮN',
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatRelativeTime(item.submittedAt),
                    style: AppTypography.caption,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.paperBorder, width: 0.5),
                    ),
                    child: Text(
                      'Lý do giữ: ${item.reviewReason}',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isNote ? Colors.transparent : AppColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: isNote ? null : Border.all(color: AppColors.paperBorder, width: 0.5),
                ),
                child: Text(
                  item.content,
                  style: AppTypography.bodyMedium,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: !_hasModerationCallback
                        ? null
                        : () => _showActionWithReasonDialog(
                              context: context,
                              title: isNote ? 'Từ chối tờ giấy' : 'Từ chối tin nhắn',
                              content: isNote
                                  ? 'Tờ giấy này sẽ không được xuất bản lên bức tường chung.'
                                  : 'Tin nhắn này sẽ bị từ chối và không chuyển tiếp tới người nhận.',
                              confirmLabel: 'Từ chối',
                              isDestructive: true,
                              onConfirm: (reason) => _handleModerate(
                                targetType: item.targetType,
                                targetId: item.targetId,
                                action: 'reject',
                                reason: reason,
                              ),
                            ),
                    child: Text(
                      'Từ chối',
                      style: AppTypography.caption.copyWith(color: AppColors.pink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.paperSage,
                      foregroundColor: AppColors.ink,
                      elevation: 0,
                    ),
                    onPressed: !_hasModerationCallback
                        ? null
                        : () => _showActionWithReasonDialog(
                              context: context,
                              title: isNote ? 'Duyệt xuất bản tờ giấy' : 'Duyệt gửi tin nhắn',
                              content: isNote
                                  ? 'Tờ giấy sẽ được dán công khai lên ô đã chọn trên bức tường.'
                                  : 'Tin nhắn sẽ được chuyển phát tới hộp thư của người nhận.',
                              confirmLabel: 'Phê duyệt',
                              onConfirm: (reason) => _handleModerate(
                                targetType: item.targetType,
                                targetId: item.targetId,
                                action: 'approve',
                                reason: reason,
                              ),
                            ),
                    child: Text(
                      isNote ? 'Duyệt xuất bản' : 'Duyệt gửi',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    return widget.onRefresh != null
        ? RefreshIndicator(onRefresh: widget.onRefresh!, color: AppColors.ink, child: content)
        : content;
  }

  /// Hàng đợi 2: Xử lý yêu cầu xóa tài khoản
  Widget _buildDeletionQueue() {
    final list = widget.deletionQueue;

    if (list == null || list.isEmpty) {
      return const ChibiEmptyState(
        icon: Icons.delete_sweep_outlined,
        title: 'Không có yêu cầu xóa',
        description: 'Hiện không có tài khoản nào gửi yêu cầu xóa dữ liệu cần xử lý.',
      );
    }

    final content = ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final item = list[index];

        return PaperSheet(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_off_outlined, size: 18, color: AppColors.inkSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Mã tham chiếu: ${item.opaqueAccountRef}',
                    style: AppTypography.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    _formatRelativeTime(item.requestedAt),
                    style: AppTypography.caption,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Trạng thái hiện tại: ${item.status}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onProcessDeletion == null
                        ? null
                        : () => _showActionWithReasonDialog(
                              context: context,
                              title: 'Tạm hoãn xử lý',
                              content: 'Đưa yêu cầu xóa vào trạng thái tạm hoãn chờ rà soát bổ sung.',
                              confirmLabel: 'Tạm hoãn',
                              onConfirm: (reason) =>
                                  widget.onProcessDeletion!(item.requestId, 'hold', reason),
                            ),
                    child: const Text('Tạm hoãn', style: AppTypography.caption),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onProcessDeletion == null
                        ? null
                        : () => _showActionWithReasonDialog(
                              context: context,
                              title: 'Bắt đầu xử lý xóa',
                              content:
                                  'Bắt đầu quy trình xử lý xóa: tạm khóa tài khoản và ẩn nội dung liên quan trong thời gian lưu trữ theo quy định (không tuyên bố đã hoàn tất xóa vĩnh viễn).',
                              confirmLabel: 'Bắt đầu xử lý',
                              isDestructive: true,
                              onConfirm: (reason) =>
                                  widget.onProcessDeletion!(item.requestId, 'start_processing', reason),
                            ),
                    child: Text(
                      'Bắt đầu xử lý',
                      style: AppTypography.caption.copyWith(color: AppColors.pink, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    return widget.onRefresh != null
        ? RefreshIndicator(onRefresh: widget.onRefresh!, color: AppColors.ink, child: content)
        : content;
  }
}
