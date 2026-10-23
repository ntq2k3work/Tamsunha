import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Khung ứng dụng chính (App Shell) chứa thanh điều hướng 3 mục: Tường, Hộp thư, Của tôi.
/// Phục vụ contract điều hướng cho Router ráp nối sau.
class AppShell extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.paperSurface,
          border: Border(
            top: BorderSide(color: AppColors.paperBorder, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view_rounded),
                selectedIcon: Icon(Icons.grid_view_sharp),
                label: 'Tường',
              ),
              NavigationDestination(
                icon: Icon(Icons.mail_outline_rounded),
                selectedIcon: Icon(Icons.mail_rounded),
                label: 'Hộp thư',
              ),
              NavigationDestination(
                icon: Icon(Icons.sticky_note_2_outlined),
                selectedIcon: Icon(Icons.sticky_note_2_rounded),
                label: 'Của tôi',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
