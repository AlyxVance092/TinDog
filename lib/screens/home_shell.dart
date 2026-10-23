import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screens.dart';
import 'discover_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.repository,
    required this.email,
    required this.dark,
    required this.onTheme,
  });
  final TinDogRepository repository;
  final String email;
  final bool dark;
  final VoidCallback onTheme;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selected = 0;
  bool _chatOpen = false;

  Future<void> _openChat(String dogId, String name) async {
    if (_chatOpen) return;
    setState(() => _chatOpen = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            repository: widget.repository,
            dogId: dogId,
            name: name,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _chatOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DiscoverScreen(
        repository: widget.repository,
        onChat: _openChat,
        active: _selected == 0 && !_chatOpen,
      ),
      MatchesScreen(
        repository: widget.repository,
        onChat: _openChat,
        onExplore: () => setState(() => _selected = 0),
      ),
      ChatListScreen(repository: widget.repository, onChat: _openChat),
      ProfileScreen(
        repository: widget.repository,
        email: widget.email,
        dark: widget.dark,
        onTheme: widget.onTheme,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _selected,
                children: [
                  for (var index = 0; index < pages.length; index++)
                    HeroMode(
                      enabled: index == _selected,
                      child: TickerMode(
                        enabled: index == _selected,
                        child: pages[index],
                      ),
                    ),
                ],
              ),
            ),
            _BottomDock(
              selected: _selected,
              onSelect: (index) => setState(() => _selected = index),
              dark: widget.dark,
              onTheme: widget.onTheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.selected,
    required this.onSelect,
    required this.dark,
    required this.onTheme,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  final bool dark;
  final VoidCallback onTheme;
  static const _items = <(IconData, String)>[
    (Icons.explore_rounded, 'Explorar'),
    (Icons.favorite_rounded, 'Matches'),
    (Icons.chat_bubble_rounded, 'Chat'),
    (Icons.person_rounded, 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 8, 15, 7),
    child: GlassCard(
      radius: 25,
      padding: const EdgeInsets.all(7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const themeWidth = 42.0;
          const themeGap = 5.0;
          final navigationWidth = constraints.maxWidth - themeWidth - themeGap;
          final itemWidth = navigationWidth / _items.length;
          return SizedBox(
            height: 57,
            child: Row(
              children: [
                SizedBox(
                  width: navigationWidth,
                  height: 57,
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        left: selected * itemWidth,
                        top: 0,
                        bottom: 0,
                        width: itemWidth,
                        duration: Duration(
                          milliseconds: motionReduced ? 0 : 350,
                        ),
                        curve: Curves.easeOutBack,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: TinColors.peach.withValues(
                              alpha:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? .13
                                  : .73,
                            ),
                            borderRadius: BorderRadius.circular(19),
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(_items.length, (index) {
                          final active = index == selected;
                          final item = _items[index];
                          return Expanded(
                            child: PressScale(
                              onTap: () => onSelect(index),
                              child: SizedBox(
                                height: 56,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedScale(
                                      scale: active && !motionReduced
                                          ? 1.13
                                          : 1,
                                      duration: const Duration(
                                        milliseconds: 260,
                                      ),
                                      curve: Curves.elasticOut,
                                      child: Icon(
                                        item.$1,
                                        size: 21,
                                        color: active
                                            ? TinColors.coral
                                            : Theme.of(context).hintColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.$2,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: active
                                            ? FontWeight.w900
                                            : FontWeight.w600,
                                        color: active
                                            ? TinColors.coral
                                            : Theme.of(context).hintColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: themeGap),
                PressScale(
                  onTap: onTheme,
                  child: Tooltip(
                    message: dark
                        ? 'Cambiar a modo claro'
                        : 'Cambiar a modo oscuro',
                    child: Container(
                      width: themeWidth,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: .08)
                            : TinColors.peach.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: TinColors.coral.withValues(alpha: .12),
                        ),
                      ),
                      child: Icon(
                        dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        color: TinColors.coral,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
