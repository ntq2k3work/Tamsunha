import 'package:flutter/material.dart';
import '../../../core/domain/conversation.dart';
import '../../../core/domain/message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/chibi_empty_state.dart';

/// Màn hình Trò chuyện Ẩn danh 1:1 (S09 — Conversation).
///
/// Tuân thủ nghiêm ngặt các nguyên tắc bảo mật và giới hạn theo ALL_IN_ONE_SPEC.md §4.4:
/// 1. Ẩn danh hoàn toàn: Không có nickname, ảnh đại diện, hay trang cá nhân.
/// 2. Hạn mức streak 3 tin: Người dùng chỉ được gửi tối đa 3 tin liên tiếp nếu người kia chưa trả lời.
/// 3. Không phơi bày trạng thái nhạy cảm: Tuyệt đối KHÔNG có Typing indicator, Last seen, hay Read receipts.
/// 4. Độc lập với backend: Nhận trạng thái từ [Conversation] và danh sách [Message].
class ConversationScreen extends StatefulWidget {
  /// Trạng thái hội thoại và hạn mức tin nhắn hiện tại.
  final Conversation conversation;

  /// Danh sách tin nhắn theo thứ tự thời gian.
  final List<Message> messages;

  /// Nội dung tờ giấy đã kết nối/mở đầu cuộc trò chuyện (nếu có, không chứa ID hay dữ liệu cá nhân).
  final String? sourceNoteContent;

  /// Đang gửi tin nhắn qua mạng.
  final bool isSubmitting;

  /// Thông báo lỗi từ server nếu có.
  final String? errorMessage;

  /// Callback gửi tin nhắn mới.
  final Future<void> Function(String)? onSendMessage;

  /// Callback đóng hội thoại.
  final VoidCallback? onCloseConversation;

  /// Callback chặn đối phương hai chiều.
  final VoidCallback? onBlockPartner;

  /// Callback báo cáo cuộc trò chuyện (toàn bộ hội thoại).
  final VoidCallback? onReport;

  /// Callback báo cáo người dùng ẩn danh đối phương.
  final VoidCallback? onReportUser;

  /// Callback báo cáo một tin nhắn cụ thể của đối phương.
  final void Function(String messageId)? onReportMessage;

  /// Callback quay lại danh sách hộp thư.
  final VoidCallback? onBack;

  const ConversationScreen({
    super.key,
    required this.conversation,
    this.messages = const <Message>[],
    this.sourceNoteContent,
    this.isSubmitting = false,
    this.errorMessage,
    this.onSendMessage,
    this.onCloseConversation,
    this.onBlockPartner,
    this.onReport,
    this.onReportUser,
    this.onReportMessage,
    this.onBack,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  bool _isSending = false;
  String? _localError;

  int get _graphemeCount => _textController.text.characters.length;
  bool get _isContentEmpty => _textController.text.trim().isEmpty;
  bool get _isContentOverLimit => _graphemeCount > 500;
  bool get _isContentValid => !_isContentEmpty && !_isContentOverLimit;

  bool get _effectiveSubmitting => widget.isSubmitting || _isSending;
  bool get _isInputEnabled =>
      widget.conversation.canSend && !_effectiveSubmitting && widget.onSendMessage != null;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textController.addListener(_onTextChanged);
    _scrollController = ScrollController();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty ||
        text.characters.length > 500 ||
        !widget.conversation.canSend ||
        _effectiveSubmitting ||
        widget.onSendMessage == null) {
      return;
    }

    setState(() {
      _isSending = true;
      _localError = null;
    });

    try {
      await widget.onSendMessage!(text);
      if (mounted) {
        _textController.clear();
        setState(() => _isSending = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _localError = e.toString().replaceFirst('Exception: ', '');
          // Giữ nguyên bản nháp trong _textController khi gửi thất bại
        });
      }
    }
  }

  static String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isInputEnabled = _isInputEnabled;
    final displayError = _localError ?? widget.errorMessage;
    final remaining = widget.conversation.remainingOutbound;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trò chuyện ẩn danh', style: AppTypography.titleMedium),
            Text('Không lưu hồ sơ công khai', style: AppTypography.caption),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: widget.onBack ?? () => Navigator.maybePop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            color: AppColors.paperSurface,
            onSelected: (value) {
              if (value == 'close') widget.onCloseConversation?.call();
              if (value == 'block') widget.onBlockPartner?.call();
              if (value == 'report') widget.onReport?.call();
              if (value == 'report_user') widget.onReportUser?.call();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 18, color: AppColors.inkSecondary),
                    SizedBox(width: 10),
                    Text('Báo cáo cuộc trò chuyện'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'report_user',
                child: Row(
                  children: [
                    Icon(Icons.person_off_outlined, size: 18, color: AppColors.inkSecondary),
                    SizedBox(width: 10),
                    Text('Báo cáo người dùng'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, size: 18, color: AppColors.pink),
                    SizedBox(width: 10),
                    Text('Chặn đối phương'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'close',
                child: Row(
                  children: [
                    Icon(Icons.close_rounded, size: 18, color: AppColors.inkSecondary),
                    SizedBox(width: 10),
                    Text('Đóng trò chuyện'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh chỉ báo hạn mức 3 tin nhắn liên tiếp (§4.4)
            _buildStreakBanner(remaining),

            // Context strip hiển thị nội dung tờ giấy đã kết nối/mở đầu trò chuyện (S09)
            if (widget.sourceNoteContent != null &&
                widget.sourceNoteContent!.trim().isNotEmpty)
              _buildSourceNoteStrip(widget.sourceNoteContent!.trim()),

            // Thông báo lỗi nếu có
            if (displayError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.pink,
                child: Text(
                  displayError,
                  style: AppTypography.caption,
                  textAlign: TextAlign.center,
                ),
              ),

            // Danh sách tin nhắn
            Expanded(
              child: widget.messages.isEmpty
                  ? const ChibiEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Bắt đầu cuộc trò chuyện',
                      description:
                          'Hãy chia sẻ một cách chân thành và tôn trọng. Bạn có tối đa 3 tin nhắn liên tiếp cho đến khi người kia phản hồi.',
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: widget.messages.length,
                      itemBuilder: (context, index) {
                        final msg = widget.messages[index];
                        return _buildMessageBubble(msg);
                      },
                    ),
            ),

            // Thanh nhập tin nhắn
            _buildInputArea(isInputEnabled, remaining),
          ],
        ),
      ),
    );
  }

  /// Dải thông tin hiển thị nội dung tờ giấy đã kết nối/mở đầu cuộc trò chuyện (S09).
  /// Tuyệt đối không phơi bày ID hoặc thông tin cá nhân của người viết.
  Widget _buildSourceNoteStrip(String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.paperSage,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.paperBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sticky_note_2_outlined,
            size: 18,
            color: AppColors.ink,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bắt đầu từ tờ giấy:',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '“$content”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thanh hiển thị hạn mức streak (§4.4)
  Widget _buildStreakBanner(int remaining) {
    final isLocked = remaining == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isLocked ? AppColors.paperButter : AppColors.paperSurface,
        border: const Border(
          bottom: BorderSide(color: AppColors.paperBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLocked ? Icons.hourglass_top_rounded : Icons.shield_outlined,
            size: 16,
            color: AppColors.inkSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLocked
                  ? 'Đã đạt hạn mức 3 tin liên tiếp. Chờ đối phương phản hồi để gửi tiếp.'
                  : 'Hạn mức: Bạn có thể gửi thêm $remaining/3 tin liên tiếp.',
              style: AppTypography.caption.copyWith(
                fontWeight: isLocked ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bong bóng tin nhắn phong cách giấy chibi
  Widget _buildMessageBubble(Message msg) {
    final isMine = msg.isMine;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? AppColors.paperButter : AppColors.paperSurface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
                border: Border.all(
                  color: isMine ? AppColors.ink.withValues(alpha: 0.15) : AppColors.paperBorder,
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    msg.body,
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(msg.createdAt),
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Nút báo cáo accessible cho tin nhắn của người kia (hit target >=44, không cho báo cáo tin của mình)
          if (!isMine && widget.onReportMessage != null) ...[
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Báo cáo tin nhắn',
              child: IconButton(
                icon: const Icon(
                  Icons.flag_outlined,
                  size: 16,
                  color: AppColors.inkSecondary,
                ),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                tooltip: 'Báo cáo tin nhắn',
                onPressed: () => widget.onReportMessage!(msg.id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Khung nhập liệu với bộ đếm ký tự (1 - 500 graphemes theo ALL_IN_ONE_SPEC.md)
  Widget _buildInputArea(bool isInputEnabled, int remaining) {
    final count = _graphemeCount;
    final isOverLimit = _isContentOverLimit;
    final canSubmit = isInputEnabled && _isContentValid;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.paperSurface,
        border: Border(
          top: BorderSide(color: AppColors.paperBorder, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  enabled: isInputEnabled,
                  maxLines: 4,
                  minLines: 1,
                  style: AppTypography.bodyMedium,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: widget.onSendMessage == null
                        ? 'Dịch vụ tin nhắn hiện không khả dụng'
                        : (_effectiveSubmitting
                            ? 'Đang gửi tin nhắn...'
                            : (widget.conversation.canSend
                                ? 'Nhập tin nhắn (tối đa 500 ký tự)...'
                                : 'Chờ phản hồi để gửi tiếp...')),
                    hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.inkSecondary),
                    filled: true,
                    fillColor: isInputEnabled
                        ? AppColors.canvas
                        : AppColors.paperBorder.withValues(alpha: 0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.paperBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.paperBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
                    ),
                  ),
                  onSubmitted: canSubmit ? (_) => _handleSend() : null,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _effectiveSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.ink),
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                color: canSubmit ? AppColors.ink : AppColors.inkSecondary,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: canSubmit ? _handleSend : null,
              ),
            ],
          ),
          // Bộ đếm grapheme live dưới ô nhập
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 52, left: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isOverLimit)
                  Text(
                    'Tin nhắn đã vượt quá giới hạn 500 ký tự',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.pink,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Text(
                  '$count/500',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: isOverLimit
                        ? AppColors.pink
                        : (count > 0 ? AppColors.ink : AppColors.inkSecondary),
                    fontWeight: isOverLimit ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
