import 'package:flutter/material.dart';

import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import 'caretaker_dashboard_screen.dart';
import 'dashboard_screen.dart';
import 'face_recognition_screen.dart';
import 'memory_screen.dart';
import 'patient_dashboard_screen.dart';
import 'private_info_screen.dart';
import 'profile_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';
import 'voice_screen.dart';

// ---------------------------------------------------------------------------
// Navigation destinations
// ---------------------------------------------------------------------------

List<_NavDest> _getDestinations(bool isCaregiver) {
  if (isCaregiver) {
    return const [
      _NavDest(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        label: 'Care Home',
      ),
      _NavDest(icon: Icons.mic_none, activeIcon: Icons.mic, label: 'Assistant'),
      _NavDest(
        icon: Icons.checklist_rtl_outlined,
        activeIcon: Icons.checklist_rtl,
        label: 'Tasks',
      ),
      _NavDest(
        icon: Icons.auto_stories_outlined,
        activeIcon: Icons.auto_stories,
        label: 'Memory',
      ),
      _NavDest(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
      ),
      _NavDest(
        icon: Icons.health_and_safety_outlined,
        activeIcon: Icons.health_and_safety,
        label: 'Medical',
      ),
      _NavDest(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Settings',
      ),
    ];
  }
  return const [
    _NavDest(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _NavDest(icon: Icons.mic_none, activeIcon: Icons.mic, label: 'Talk'),
    _NavDest(
      icon: Icons.alarm_outlined,
      activeIcon: Icons.alarm,
      label: 'Reminders',
    ),
    _NavDest(
      icon: Icons.auto_stories_outlined,
      activeIcon: Icons.auto_stories,
      label: 'Memories',
    ),
    _NavDest(icon: Icons.face_outlined, activeIcon: Icons.face, label: 'Faces'),
    _NavDest(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
    _NavDest(
      icon: Icons.health_and_safety_outlined,
      activeIcon: Icons.health_and_safety,
      label: 'Private',
    ),
    _NavDest(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
    ),
  ];
}

/// Kept separate from the widget tree so role-specific navigation can be
/// verified without rendering a dashboard. Caregivers must never receive a
/// Vision destination; patients retain it.
List<String> navigationLabelsForRole({required bool isCaregiver}) =>
    _getDestinations(isCaregiver)
        .map((destination) => destination.label)
        .toList(growable: false);

class _NavDest {
  const _NavDest({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

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
    final auth = AuthScope.of(context);
    final isCaregiver = auth.user?.role == 'caregiver';
    final destinations = _getDestinations(isCaregiver);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width >= 1024) {
              return _ExpandedShell(
                controller: controller,
                destinations: destinations,
                isCaregiver: isCaregiver,
              );
            } else if (width >= 600) {
              return _MediumShell(
                controller: controller,
                destinations: destinations,
                isCaregiver: isCaregiver,
              );
            } else {
              return _CompactShell(
                controller: controller,
                destinations: destinations,
              );
            }
          },
        );
      },
    );
  }

  static Widget _buildPage(
    BuildContext context,
    int index,
    AssistantController controller,
  ) {
    final auth = AuthScope.of(context);
    final isCaregiver = auth.user?.role == 'caregiver';

    if (isCaregiver) {
      switch (index) {
        case 0:
          return CaretakerDashboardScreen(onNavigate: controller.selectNav);
        case 1:
          return const VoiceScreen();
        case 2:
          return const RemindersScreen();
        case 3:
          return const MemoryScreen();
        case 4:
          return const ProfileScreen();
        case 5:
          return const PrivateInfoScreen();
        case 6:
          return const SettingsScreen();
        default:
          return CaretakerDashboardScreen(onNavigate: controller.selectNav);
      }
    }
    switch (index) {
      case 0:
        return PatientDashboardScreen(onNavigate: controller.selectNav);
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
        if (isCaregiver) {
          return CaretakerDashboardScreen(onNavigate: controller.selectNav);
        }
        return PatientDashboardScreen(onNavigate: controller.selectNav);
    }
  }
}

// ---------------------------------------------------------------------------
// Compact layout – bottom navigation bar (phones)
// ---------------------------------------------------------------------------

class _CompactShell extends StatelessWidget {
  const _CompactShell({required this.controller, required this.destinations});

  final AssistantController controller;
  final List<_NavDest> destinations;

  @override
  Widget build(BuildContext context) {
    final index = controller.navIndex.clamp(0, destinations.length - 1);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < destinations.length; i++)
            AppShell._buildPage(context, i, controller),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: controller.selectNav,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final dest in destinations)
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
  const _MediumShell({
    required this.controller,
    required this.destinations,
    required this.isCaregiver,
  });

  final AssistantController controller;
  final List<_NavDest> destinations;
  final bool isCaregiver;

  @override
  Widget build(BuildContext context) {
    final index = controller.navIndex.clamp(0, destinations.length - 1);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: controller.selectNav,
            extended: false,
            leading: _RailLogo(isCaregiver: isCaregiver),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final dest in destinations)
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
                for (var i = 0; i < destinations.length; i++)
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
  const _ExpandedShell({
    required this.controller,
    required this.destinations,
    required this.isCaregiver,
  });

  final AssistantController controller;
  final List<_NavDest> destinations;
  final bool isCaregiver;

  @override
  Widget build(BuildContext context) {
    final index = controller.navIndex.clamp(0, destinations.length - 1);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: controller.selectNav,
            extended: true,
            minExtendedWidth: 200,
            leading: _RailLogo(extended: true, isCaregiver: isCaregiver),
            trailing: _RailStatus(controller: controller),
            destinations: [
              for (final dest in destinations)
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
                for (var i = 0; i < destinations.length; i++)
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
  const _RailLogo({this.extended = false, this.isCaregiver = false});

  final bool extended;
  final bool isCaregiver;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final title = isCaregiver ? 'Care Management' : 'Memory Care';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: extended
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCaregiver
                      ? Icons.healing_rounded
                      : Icons.local_hospital_rounded,
                  color: color,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            )
          : Icon(
              isCaregiver
                  ? Icons.healing_rounded
                  : Icons.local_hospital_rounded,
              color: color,
              size: 26,
            ),
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
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
