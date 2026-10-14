import 'package:flutter/material.dart';

import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'face_recognition_screen.dart';
import 'memory_screen.dart';
import 'private_info_screen.dart';
import 'profile_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';
import 'voice_screen.dart';

// ---------------------------------------------------------------------------
// Navigation destinations
// ---------------------------------------------------------------------------

const _kDestinations = <_NavDest>[
  _NavDest(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
  _NavDest(icon: Icons.mic_none, activeIcon: Icons.mic, label: 'Assistant'),
  _NavDest(icon: Icons.alarm_outlined, activeIcon: Icons.alarm, label: 'Reminders'),
  _NavDest(icon: Icons.auto_stories_outlined, activeIcon: Icons.auto_stories, label: 'Memory'),
  _NavDest(icon: Icons.face_outlined, activeIcon: Icons.face, label: 'Faces'),
  _NavDest(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  _NavDest(icon: Icons.health_and_safety_outlined, activeIcon: Icons.health_and_safety, label: 'Private'),
  _NavDest(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
];

class _NavDest {
  const _NavDest({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

// ---------------------------------------------------------------------------
// AppShell – chooses layout based on screen width
// ---------------------------------------------------------------------------

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width >= 1024) {
              return _ExpandedShell(controller: controller);
            } else if (width >= 600) {
              return _MediumShell(controller: controller);
            } else {
              return _CompactShell(controller: controller);
            }
          },
        );
      },
    );
  }

  static Widget _buildPage(BuildContext context, int index, AssistantController controller) {
    switch (index) {
      case 0:
        return DashboardScreen(onNavigate: controller.selectNav);
      case 1:
        return const VoiceScreen();
      case 2:
        return const RemindersScreen();
      case 3:
        return const MemoryScreen();
      case 4:
        return const FaceRecognitionScreen();
      case 5:
        return const ProfileScreen();
      case 6:
        return const PrivateInfoScreen();
      case 7:
        return const SettingsScreen();
      default:
        return DashboardScreen(onNavigate: controller.selectNav);
    }
  }
}

// ---------------------------------------------------------------------------
// Compact layout – bottom navigation bar (phones)
// ---------------------------------------------------------------------------

class _CompactShell extends StatelessWidget {
  const _CompactShell({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final index = controller.navIndex.clamp(0, _kDestinations.length - 1);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < _kDestinations.length; i++)
            AppShell._buildPage(context, i, controller),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: controller.selectNav,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final dest in _kDestinations)
            NavigationDestination(
              icon: Icon(dest.icon),
              selectedIcon: Icon(dest.activeIcon),
              label: dest.label,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Medium layout – navigation rail (tablets, small laptops)
// ---------------------------------------------------------------------------

class _MediumShell extends StatelessWidget {
  const _MediumShell({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final index = controller.navIndex.clamp(0, _kDestinations.length - 1);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: controller.selectNav,
            extended: false,
            leading: _RailLogo(),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final dest in _kDestinations)
                NavigationRailDestination(
                  icon: Icon(dest.icon),
                  selectedIcon: Icon(dest.activeIcon),
                  label: Text(dest.label),
                ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < _kDestinations.length; i++)
                  AppShell._buildPage(context, i, controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expanded layout – wide navigation rail (desktops)
// ---------------------------------------------------------------------------

class _ExpandedShell extends StatelessWidget {
  const _ExpandedShell({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final index = controller.navIndex.clamp(0, _kDestinations.length - 1);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: controller.selectNav,
            extended: true,
            minExtendedWidth: 200,
            leading: _RailLogo(extended: true),
            trailing: _RailStatus(controller: controller),
            destinations: [
              for (final dest in _kDestinations)
                NavigationRailDestination(
                  icon: Icon(dest.icon),
                  selectedIcon: Icon(dest.activeIcon),
                  label: Text(dest.label),
                ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < _kDestinations.length; i++)
                  AppShell._buildPage(context, i, controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared rail widgets
// ---------------------------------------------------------------------------

class _RailLogo extends StatelessWidget {
  const _RailLogo({this.extended = false});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: extended
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_hospital_rounded, color: color, size: 26),
                const SizedBox(width: 8),
                Text(
                  'Memory Care',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            )
          : Icon(Icons.local_hospital_rounded, color: color, size: 26),
    );
  }
}

class _RailStatus extends StatelessWidget {
  const _RailStatus({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final online = controller.link == AssistantLink.ready;
    final color = online ? AppColors.success : AppColors.warning;
    final label = online ? 'Online' : 'Offline';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
