import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// HUD nổi trên bức tường: Nút khám phá góc khác và nút dán giấy (+).
class WallHud extends StatelessWidget {
  final VoidCallback? onExploreOtherRegion;
  final VoidCallback? onEnterPlacement;
  final bool isExploring;

  const WallHud({
    super.key,
    this.onExploreOtherRegion,
    this.onEnterPlacement,
    this.isExploring = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Nút "Đến góc khác" ở phía trên giữa màn hình
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                button: true,
                label: 'Khám phá góc khác trên bức tường',
                child: Material(
                  color: AppColors.paperSurface,
                  borderRadius: BorderRadius.circular(22),
                  elevation: 0,
                  child: InkWell(
                    onTap: isExploring ? null : onExploreOtherRegion,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.paperBorder, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isExploring) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.inkSecondary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Đang tìm góc mới...',
                              style: AppTypography.bodySmall,
                            ),
                          ] else ...[
                            const Icon(
                              Icons.explore_outlined,
                              size: 18,
                              color: AppColors.ink,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Đến góc khác',
                              style: AppTypography.labelLarge,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 2. Nút dán giấy "+" ở góc dưới bên phải (Vùng chạm chuẩn >= 56x56dp)
        SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20, bottom: 20),
              child: Semantics(
                button: true,
                label: 'Dán tờ giấy mới lên tường',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
                  child: FloatingActionButton(
                    onPressed: onEnterPlacement,
                    backgroundColor: AppColors.ink,
                    foregroundColor: AppColors.paperSurface,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    tooltip: 'Dán tờ giấy mới',
                    child: const Icon(Icons.add_rounded, size: 28),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
