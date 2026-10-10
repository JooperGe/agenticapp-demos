import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/game_controller.dart';
import '../game_scope.dart';
import '../discovery/discovery_log_page.dart';
import '../galaxy3d/galaxy_map_3d_page.dart';
import '../journey/journey_page.dart';
import '../training/training_page.dart';
import 'shell_scope.dart';

/// Root navigation shell: a four-tab bottom bar over an [IndexedStack] so each
/// page keeps its state when switching tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _goToTab(int index) {
    if (index != _index) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    return ShellScope(
      goToTab: _goToTab,
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _index,
          children: const <Widget>[
            GalaxyMap3DPage(),
            JourneyPage(),
            DiscoveryLogPage(),
            TrainingPage(),
          ],
        ),
        bottomNavigationBar: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => _StarNavBar(
            index: _index,
            onTap: _goToTab,
            controller: controller,
          ),
        ),
      ),
    );
  }
}

class _StarNavBar extends StatelessWidget {
  const _StarNavBar({
    required this.index,
    required this.onTap,
    required this.controller,
  });

  final int index;
  final ValueChanged<int> onTap;
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // The journey tab shows a live badge when a voyage is in progress/arrived.
    final hasJourney = controller.activeJourney != null;
    return Container(
      decoration: const BoxDecoration(
        color: StarColors.panel,
        border: Border(top: BorderSide(color: StarColors.panelBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _NavItem(
                icon: Icons.public_rounded,
                label: '星图',
                selected: index == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.rocket_launch_rounded,
                label: '航行',
                selected: index == 1,
                badge: hasJourney,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.auto_stories_rounded,
                label: '发现',
                selected: index == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.favorite_rounded,
                label: '训练',
                selected: index == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? StarColors.cyan : StarColors.faint;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(icon, color: color, size: 24),
                if (badge)
                  Positioned(
                    right: -3,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: StarColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
