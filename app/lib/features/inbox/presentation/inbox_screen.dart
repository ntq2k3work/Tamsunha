import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/chibi_empty_state.dart';
import '../../../core/widgets/paper_sheet.dart';

/// Dữ liệu hiển thị một lời động viên nhận được trong Hộp thư.
class EncouragementInboxItem {
  final String id;
  final String messageText;
  final DateTime receivedAt;
  final String noteSnippet;
  final int? cellX;
  final int? cellY;

  const EncouragementInboxItem({
    required this.id,
    required this.messageText,
    required this.receivedAt,
    required this.noteSnippet,
    this.cellX,
    this.cellY,
  });
}

/// Dữ liệu hiển thị một cuộc hội thoại trong tab Tin nhắn của Hộp thư.
class ConversationInboxItem {
  final String conversationId;
  final String lastMessageSnippet;
  final DateTime updatedAt;
  final int unreadCount;
  final int remainingOutbound; // 0..3
  final bool isClosed;

  const ConversationInboxItem({
    required this.conversationId,
    required this.lastMessageSnippet,
    required this.updatedAt,
    this.unreadCount = 0,
    this.remainingOutbound = 3,
    this.isClosed = false,
  });
}

/// Màn hình Hộp thư (S08) — Chuyển đổi giữa Lời động viên và Tin nhắn 1:1.
///
/// Hỗ trợ typed data props cho Codex kết nối repository/realtime,
/// đồng thời giữ empty states và tương thích backward nếu chạy standalone.
class InboxScreen extends StatefulWidget {
  final int initialTab;
  final List<EncouragementInboxItem>? encouragements;
  final List<ConversationInboxItem>? conversations;
  final bool isLoading;
  final bool isLoadingMoreEncouragements;
  final bool isLoadingMoreConversations;
  final String? errorMessage;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onLoadMoreEncouragements;
  final Future<void> Function()? onLoadMoreConversations;
  final ValueChanged<String>? onOpenConversation;
  final void Function(int cellX, int cellY)? onJumpToNote;

  const InboxScreen({
    super.key,
    this.initialTab = 0,
    this.encouragements,
    this.conversations,
    this.isLoading = false,
    this.isLoadingMoreEncouragements = false,
    this.isLoadingMoreConversations = false,
    this.errorMessage,
    this.onRefresh,
    this.onLoadMoreEncouragements,
    this.onLoadMoreConversations,
    this.onOpenConversation,
    this.onJumpToNote,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late int _selectedTab;
  late final ScrollController _encouragementScrollController;
  late final ScrollController _conversationScrollController;
  bool _isCallingLoadMoreEncouragements = false;
  bool _isCallingLoadMoreConversations = false;

  bool get _isBusyEncouragements =>
      widget.isLoadingMoreEncouragements || _isCallingLoadMoreEncouragements;

  bool get _isBusyConversations =>
      widget.isLoadingMoreConversations || _isCallingLoadMoreConversations;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _encouragementScrollController = ScrollController()
      ..addListener(_onEncouragementScroll);
    _conversationScrollController = ScrollController()
      ..addListener(_onConversationScroll);
  }

  @override
  void dispose() {
    _encouragementScrollController.removeListener(_onEncouragementScroll);
    _encouragementScrollController.dispose();
    _conversationScrollController.removeListener(_onConversationScroll);
    _conversationScrollController.dispose();
    super.dispose();
  }

  void _onEncouragementScroll() {
    if (_selectedTab == 0 && _encouragementScrollController.hasClients) {
      final position = _encouragementScrollController.position;
      // Trigger tải tiếp khi cuộn gần cuối danh sách (cách đáy 200px)
      if (position.maxScrollExtent - position.pixels <= 200) {
        _triggerLoadMoreEncouragements();
      }
    }
  }

  Future<void> _triggerLoadMoreEncouragements() async {
    if (_isBusyEncouragements || widget.onLoadMoreEncouragements == null) return;
    setState(() => _isCallingLoadMoreEncouragements = true);
    try {
      await widget.onLoadMoreEncouragements!();
    } finally {
      if (mounted) {
        setState(() => _isCallingLoadMoreEncouragements = false);
      }
    }
  }

  void _onConversationScroll() {
    if (_selectedTab == 1 && _conversationScrollController.hasClients) {
      final position = _conversationScrollController.position;
      // Trigger tải tiếp khi cuộn gần cuối danh sách (cách đáy 200px)
      if (position.maxScrollExtent - position.pixels <= 200) {
        _triggerLoadMoreConversations();
      }
    }
  }

  Future<void> _triggerLoadMoreConversations() async {
    if (_isBusyConversations || widget.onLoadMoreConversations == null) return;
    setState(() => _isCallingLoadMoreConversations = true);
    try {
      await widget.onLoadMoreConversations!();
    } finally {
      if (mounted) {
        setState(() => _isCallingLoadMoreConversations = false);
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
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Hộp thư'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh chuyển tab phong cách giấy
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.paperSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.paperBorder, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedTab = 0),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedTab == 0 ? AppColors.tape : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Lời động viên',
                            style: _selectedTab == 0
                                ? AppTypography.labelLarge
                                : AppTypography.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedTab = 1),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedTab == 1 ? AppColors.tape : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Tin nhắn',
                            style: _selectedTab == 1
                                ? AppTypography.labelLarge
                                : AppTypography.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Thông báo lỗi nếu có
            if (widget.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.pink,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.paperBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.ink),
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
              ),

            // Nội dung theo Tab
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
                  : _selectedTab == 0
                      ? _buildEncouragementsList()
                      : _buildConversationsList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Danh sách Tab 0: Lời động viên nhận được
  Widget _buildEncouragementsList() {
    final list = widget.encouragements;

    if (list == null || list.isEmpty) {
      return const ChibiEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'Chưa có lời động viên nào',
        description:
            'Khi có ai đó gửi 1 trong 5 câu động viên định sẵn tới tờ giấy của bạn, nội dung ấm áp sẽ xuất hiện tại đây.',
      );
    }

    final showFooter = _isBusyEncouragements;
    final content = ListView.separated(
      controller: _encouragementScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: list.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == list.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.inkSecondary),
                ),
              ),
            ),
          );
        }

        final item = list[index];

        return PaperSheet(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    size: 16,
                    color: AppColors.inkSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatRelativeTime(item.receivedAt),
                    style: AppTypography.caption,
                  ),
                  const Spacer(),
                  if (item.cellX != null && item.cellY != null && widget.onJumpToNote != null)
                    Semantics(
                      button: true,
                      label: 'Xem vị trí tờ giấy trên tường',
                      child: InkWell(
                        onTap: () => widget.onJumpToNote!(item.cellX!, item.cellY!),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.near_me_outlined, size: 14, color: AppColors.ink),
                              SizedBox(width: 4),
                              Text('Vị trí', style: AppTypography.caption),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '“${item.messageText}”',
                style: AppTypography.titleMedium.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.paperBorder, width: 0.5),
                ),
                child: Text(
                  'Gửi đến: ${item.noteSnippet}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: AppColors.inkSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (widget.onRefresh != null) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh!,
        color: AppColors.ink,
        backgroundColor: AppColors.paperSurface,
        child: content,
      );
    }
    return content;
  }

  /// Danh sách Tab 1: Các cuộc trò chuyện 1:1
  Widget _buildConversationsList() {
    final list = widget.conversations;

    if (list == null || list.isEmpty) {
      return const ChibiEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Chưa có tin nhắn nào',
        description:
            'Các cuộc trò chuyện 1:1 xuất phát từ tờ giấy sẽ hiển thị tại đây khi bắt đầu (tối đa 3 tin liên tiếp nếu chưa được phản hồi).',
      );
    }

    final showFooter = _isBusyConversations;
    final content = ListView.separated(
      controller: _conversationScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: list.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == list.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.inkSecondary),
                ),
              ),
            ),
          );
        }

        final item = list[index];

        return InkWell(
          onTap: () => widget.onOpenConversation?.call(item.conversationId),
          borderRadius: BorderRadius.circular(16),
          child: PaperSheet(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon avatar trung tính
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.paperBorder, width: 1),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 20,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Trò chuyện ẩn danh',
                            style: AppTypography.labelLarge,
                          ),
                          const Spacer(),
                          Text(
                            _formatRelativeTime(item.updatedAt),
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.lastMessageSnippet.isNotEmpty
                            ? item.lastMessageSnippet
                            : '(Chưa có tin nhắn)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      // Hạn mức tin nhắn streak (§4.4)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: item.remainingOutbound > 0 ? AppColors.paperSage : AppColors.paperButter,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.remainingOutbound > 0
                                  ? 'Có thể gửi: ${item.remainingOutbound}/3 tin'
                                  : 'Chờ đối phương phản hồi (0/3)',
                              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                          if (item.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: AppColors.pink,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${item.unreadCount}',
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.onRefresh != null) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh!,
        color: AppColors.ink,
        backgroundColor: AppColors.paperSurface,
        child: content,
      );
    }
    return content;
  }
}
