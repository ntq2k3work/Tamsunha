import 'package:flutter/material.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/chibi_empty_state.dart';
import '../../../core/widgets/paper_sheet.dart';

/// Dữ liệu biểu diễn một tờ giấy do chính người dùng tạo (S10 — My Notes).
class MyNoteItem {
  final String id;
  final String content;
  final PaperColor paperColor;
  final String status; // 'published' | 'pending_review' | 'hidden' | 'deleted'
  final DateTime createdAt;
  final DateTime? publishedAt;
  final int? cellX;
  final int? cellY;
  final bool canEdit;
  final bool canDelete;
  final bool allowChat;

  const MyNoteItem({
    required this.id,
    required this.content,
    required this.paperColor,
    required this.status,
    required this.createdAt,
    this.publishedAt,
    this.cellX,
    this.cellY,
    this.canEdit = false,
    this.canDelete = true,
    this.allowChat = true,
  });
}

/// Màn hình Nhật ký của tôi (S10) — Danh sách các tờ giấy và hạn mức 1 note/ngày.
///
/// Hỗ trợ:
/// 1. Hiển thị hạn mức viết note trong ngày theo giờ Việt Nam (§4.2).
/// 2. Danh sách note của chính mình kèm 4 trạng thái duyệt: Đã dán, Đang kiểm tra, Đã ẩn, Đã xóa.
/// 3. Thao tác điều hướng tới vị trí note trên tường, sửa (trong 30 phút), xóa, hoặc bật/tắt chat.
class MyNotesScreen extends StatelessWidget {
  /// Đã sử dụng hạn mức viết note trong ngày hay chưa (1 note/ngày).
  final bool? dailyQuotaUsed;

  /// Danh sách các tờ giấy của người dùng.
  final List<MyNoteItem>? notes;

  /// Đang tải dữ liệu từ server.
  final bool isLoading;

  /// Thông báo lỗi từ server nếu có.
  final String? errorMessage;

  /// Callback làm mới danh sách.
  final Future<void> Function()? onRefresh;

  /// Callback di chuyển camera tường tới tọa độ của note.
  final void Function(int cellX, int cellY)? onJumpToNote;

  /// Callback mở giao diện sửa note (khi còn trong 30 phút và chưa có tương tác).
  final ValueChanged<String>? onEditNote;

  /// Callback xóa note.
  final ValueChanged<String>? onDeleteNote;

  /// Callback chuyển đổi trạng thái cho phép nhận tin nhắn từ note.
  final void Function(String id, bool allowChat)? onToggleChat;

  const MyNotesScreen({
    super.key,
    this.dailyQuotaUsed,
    this.notes,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
    this.onJumpToNote,
    this.onEditNote,
    this.onDeleteNote,
    this.onToggleChat,
  });

  static String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _confirmDelete(BuildContext context, MyNoteItem note) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paperSurface,
        title: const Text('Xác nhận xóa giấy', style: AppTypography.titleMedium),
        content: const Text(
          'Tờ giấy sẽ bị gỡ khỏi bức tường chung ngay lập tức. Bạn vẫn có thể giữ lịch sử tin nhắn liên quan nếu có.',
          style: AppTypography.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy', style: AppTypography.caption),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDeleteNote?.call(note.id);
            },
            child: Text(
              'Xóa giấy',
              style: AppTypography.caption.copyWith(color: AppColors.pink, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Tờ giấy của tôi'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thẻ tóm tắt hạn mức viết note trong ngày (giờ Việt Nam — §4.2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: PaperSheet(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.edit_calendar_outlined, size: 20, color: AppColors.ink),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Hạn mức dán giấy (giờ VN)',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: dailyQuotaUsed == true ? AppColors.paperButter : AppColors.paperSage,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.paperBorder, width: 1),
                      ),
                      child: Text(
                        dailyQuotaUsed == null
                            ? 'Chưa kết nối tài khoản'
                            : dailyQuotaUsed!
                                ? 'Đã dán hôm nay (1/1)'
                                : 'Còn 1 lượt hôm nay',
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Thông báo lỗi nếu có
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.pink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(errorMessage!, style: AppTypography.caption),
                ),
              ),

            // Danh sách các tờ giấy
            Expanded(
              child: isLoading
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
                  : _buildNotesList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesList(BuildContext context) {
    if (notes == null || notes!.isEmpty) {
      return const ChibiEmptyState(
        icon: Icons.note_alt_outlined,
        title: 'Chưa có tờ giấy nào',
        description:
            'Khi bạn dán một tờ giấy lên bức tường chung, nhật ký và trạng thái kiểm duyệt của bạn sẽ xuất hiện tại đây.',
      );
    }

    final content = ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: notes!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, index) {
        final note = notes![index];
        return _buildNoteCard(context, note);
      },
    );

    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: onRefresh!,
        color: AppColors.ink,
        backgroundColor: AppColors.paperSurface,
        child: content,
      );
    }
    return content;
  }

  Widget _buildNoteCard(BuildContext context, MyNoteItem note) {
    return PaperSheet(
      paperColor: note.paperColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Thời gian + Badge trạng thái duyệt
          Row(
            children: [
              Text(
                _formatRelativeTime(note.publishedAt ?? note.createdAt),
                style: AppTypography.caption,
              ),
              const Spacer(),
              _buildStatusBadge(note.status),
            ],
          ),
          const SizedBox(height: 10),

          // Nội dung note
          Text(
            note.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 14),

          // Hàng hành động
          Row(
            children: [
              // Xem vị trí trên tường
              if (note.cellX != null && note.cellY != null && onJumpToNote != null)
                TextButton.icon(
                  icon: const Icon(Icons.near_me_outlined, size: 16),
                  label: const Text('Xem vị trí', style: AppTypography.caption),
                  onPressed: () => onJumpToNote!(note.cellX!, note.cellY!),
                ),

              // Sửa note (trong 30 phút hợp lệ)
              if (note.canEdit && onEditNote != null)
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Sửa', style: AppTypography.caption),
                  onPressed: () => onEditNote!(note.id),
                ),

              const Spacer(),

              // Xóa note
              if (note.canDelete && onDeleteNote != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: AppColors.inkSecondary,
                  tooltip: 'Xóa giấy',
                  onPressed: () => _confirmDelete(context, note),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final String label;
    final Color badgeColor;

    switch (status) {
      case 'published':
        label = 'Đã dán trên tường';
        badgeColor = AppColors.paperSage;
        break;
      case 'pending_review':
        label = 'Đang kiểm tra';
        badgeColor = AppColors.paperButter;
        break;
      case 'hidden':
        label = 'Đã ẩn';
        badgeColor = AppColors.paperBorder;
        break;
      case 'deleted':
        label = 'Đã xóa';
        badgeColor = AppColors.paperPink;
        break;
      default:
        label = status;
        badgeColor = AppColors.paperSurface;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.paperBorder, width: 0.5),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
