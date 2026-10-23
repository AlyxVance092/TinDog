import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../models/dog.dart';
import '../theme.dart';
import '../widgets/common.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.repository,
    required this.onChat,
    required this.onExplore,
  });
  final TinDogRepository repository;
  final void Function(String id, String name) onChat;
  final VoidCallback onExplore;
  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  int _tab = 0;
  int _matchCount = 0;
  int _pendingRequestCount = 0;
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
    _refreshCounts();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      _tab == 0 ? widget.repository.matches() : widget.repository.requests();

  Future<void> _refreshCounts() async {
    final values = await Future.wait([
      widget.repository.matches(),
      widget.repository.requests(),
    ]);
    if (!mounted) return;
    setState(() {
      _matchCount = values[0].length;
      _pendingRequestCount = values[1]
          .where(
            (request) =>
                request['status'] == 'pending' &&
                request['direction'] != 'sent',
          )
          .length;
    });
  }

  void _changeTab(int value) {
    if (value == _tab) return;
    setState(() {
      _tab = value;
      _future = _load();
    });
  }

  void _refresh() {
    setState(() => _future = _load());
    _refreshCounts();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 9, 18, 1),
    child: Column(
      children: [
        PageHeading(
          'Conexiones',
          subtitle: _tab == 0
              ? 'Conocerse empieza aquí.'
              : 'Invitaciones para revisar.',
          trailing: _ConnectionCountPill(
            count: _matchCount + _pendingRequestCount,
          ),
        ),
        const SizedBox(height: 14),
        _ConnectionTabs(
          selected: _tab,
          matches: _matchCount,
          requests: _pendingRequestCount,
          onSelect: _changeTab,
        ),
        const SizedBox(height: 13),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return ListView.separated(
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, _) =>
                      const SkeletonCard(height: 83, radius: 20),
                );
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite_border_rounded,
                          color: TinColors.coral,
                          size: 38,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _tab == 0
                              ? 'Tus nuevos matches aparecerán aquí.'
                              : 'Todavía no tienes solicitudes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: PrimaryButton(
                            label: 'Explorar perros',
                            icon: Icons.explore_rounded,
                            height: 48,
                            onPressed: widget.onExplore,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 14),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return StaggeredIn(
                    index: index,
                    child: _tab == 0
                        ? _MatchTile(
                            item: item,
                            repository: widget.repository,
                            onTap: () => widget.onChat(
                              item['dogId'] as String,
                              item['name'] as String,
                            ),
                          )
                        : _RequestTile(
                            item: item,
                            repository: widget.repository,
                            onChanged: _refresh,
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ConnectionCountPill extends StatelessWidget {
  const _ConnectionCountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: TinColors.coral.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: TinColors.coral.withValues(alpha: .12)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.favorite_rounded, color: TinColors.coral, size: 14),
        const SizedBox(width: 5),
        AnimatedSwitcher(
          duration: Duration(milliseconds: motionReduced ? 0 : 220),
          child: Text(
            '$count',
            key: ValueKey(count),
            style: const TextStyle(
              color: TinColors.coral,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ConnectionTabs extends StatelessWidget {
  const _ConnectionTabs({
    required this.selected,
    required this.matches,
    required this.requests,
    required this.onSelect,
  });
  final int selected;
  final int matches;
  final int requests;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;
        return Container(
          height: 74,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: .055)
                : const Color(0xFFEFE7E0).withValues(alpha: .84),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(
              color: dark ? Colors.white.withValues(alpha: .07) : Colors.white,
            ),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                left: selected * itemWidth,
                top: 0,
                bottom: 0,
                width: itemWidth,
                duration: Duration(milliseconds: motionReduced ? 0 : 380),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: motionReduced ? 0 : 300),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: selected == 0
                          ? [TinColors.coral, const Color(0xFFE84932)]
                          : [TinColors.green, const Color(0xFF078A61)],
                    ),
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (selected == 0 ? TinColors.coral : TinColors.green)
                                .withValues(alpha: .22),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ConnectionTabItem(
                      icon: Icons.favorite_rounded,
                      title: 'Matches',
                      subtitle: 'Conexiones mutuas',
                      count: matches,
                      selected: selected == 0,
                      onTap: () => onSelect(0),
                    ),
                  ),
                  Expanded(
                    child: _ConnectionTabItem(
                      icon: Icons.mark_email_unread_rounded,
                      title: 'Solicitudes',
                      subtitle: 'Por revisar',
                      count: requests,
                      selected: selected == 1,
                      onTap: () => onSelect(1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectionTabItem extends StatelessWidget {
  const _ConnectionTabItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = title == 'Matches' ? TinColors.coral : TinColors.green;
    final foreground = selected ? Colors.white : Theme.of(context).hintColor;
    return PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: motionReduced ? 0 : 240),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: .2)
                    : accent.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: selected ? .76 : .8),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            AnimatedContainer(
              duration: Duration(milliseconds: motionReduced ? 0 : 220),
              constraints: const BoxConstraints(minWidth: 23),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: .2)
                    : accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? Colors.white : accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.item,
    required this.repository,
    required this.onTap,
  });
  final Map<String, dynamic> item;
  final TinDogRepository repository;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    child: GlassCard(
      radius: 21,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Row(
        children: [
          _DogAvatar(
            repository: repository,
            dogId: item['dogId'] as String,
            size: 56,
            online: true,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String? ?? 'Match',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item['lastMessage'] as String? ?? '¡Ya pueden platicar!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item['time'] as String? ?? '',
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 8),
              if ((item['unread'] as int? ?? 0) > 0)
                Container(
                  width: 19,
                  height: 19,
                  decoration: const BoxDecoration(
                    color: TinColors.coral,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${item['unread']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: TinColors.coral,
                  size: 18,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RequestTile extends StatefulWidget {
  const _RequestTile({
    required this.item,
    required this.repository,
    required this.onChanged,
  });
  final Map<String, dynamic> item;
  final TinDogRepository repository;
  final VoidCallback onChanged;
  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile>
    with SingleTickerProviderStateMixin {
  bool _opening = false;
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: motionReduced ? 1 : 820),
  );

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  Future<void> _accept(String id) async {
    if (_opening) return;
    HapticFeedback.mediumImpact();
    setState(() => _opening = true);
    await _open.forward(from: 0);
    if (!mounted) return;
    try {
      await widget.repository.answerRequest(id, accept: true);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final id = item['dogId'] as String;
    final sent = item['direction'] == 'sent';
    final status = item['status'] as String? ?? 'pending';
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          Row(
            children: [
              _DogAvatar(repository: widget.repository, dogId: id, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] as String? ?? 'Perfil',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      item['time'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(sent && status == 'pending' ? 'Enviada' : status),
            ],
          ),
          if (!sent) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item['message'] as String? ??
                    'Solicitud para conocerse y platicar.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              if (_opening)
                _OpeningRequestEffect(animation: _open)
              else
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          onPressed: () async {
                            HapticFeedback.selectionClick();
                            await widget.repository.answerRequest(
                              id,
                              accept: false,
                            );
                            widget.onChanged();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).hintColor,
                            side: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Ahora no'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: () => _accept(id),
                          icon: const Icon(Icons.check_rounded, size: 17),
                          label: const Text('Aceptar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: TinColors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ] else if (status == 'accepted')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '¡Solicitud aceptada! Ya pueden chatear.',
                style: TextStyle(
                  color: TinColors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpeningRequestEffect extends StatelessWidget {
  const _OpeningRequestEffect({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: TinColors.peach.withValues(alpha: .34),
      borderRadius: BorderRadius.circular(16),
    ),
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(animation.value);
        return Row(
          children: [
            SizedBox(
              width: 42,
              height: 38,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .001)
                        ..rotateX(-progress * .9),
                      child: Icon(
                        progress > .46
                            ? Icons.mark_email_read_rounded
                            : Icons.mail_rounded,
                        color: TinColors.coral,
                        size: 25,
                      ),
                    ),
                  ),
                  for (var i = 0; i < 4; i++)
                    Positioned(
                      left: 12 + i * 5.5,
                      top: 25 - progress * (12 + i * 4),
                      child: Opacity(
                        opacity: (progress * 1.8 - i * .16).clamp(0.0, 1.0),
                        child: Icon(
                          i.isEven
                              ? Icons.favorite_rounded
                              : Icons.auto_awesome_rounded,
                          size: 9 + i % 2 * 3,
                          color: i.isEven ? TinColors.coral : Colors.amber,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Abriendo una nueva conexión…',
                style: TextStyle(
                  color: TinColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final accepted = status == 'accepted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: (accepted ? TinColors.green : TinColors.coral).withValues(
          alpha: .12,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status == 'pending'
            ? 'Pendiente'
            : status == 'declined'
            ? 'Cerrada'
            : status,
        style: TextStyle(
          color: accepted ? TinColors.green : TinColors.coral,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DogAvatar extends StatelessWidget {
  const _DogAvatar({
    required this.repository,
    required this.dogId,
    required this.size,
    this.online = false,
  });
  final TinDogRepository repository;
  final String dogId;
  final double size;
  final bool online;
  @override
  Widget build(BuildContext context) => FutureBuilder<Dog?>(
    future: repository.dogById(dogId),
    builder: (context, snapshot) {
      final dog = snapshot.data;
      return Stack(
        children: [
          Hero(
            tag: 'chat-dog-$dogId',
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: TinColors.peach,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: dog == null
                  ? const Icon(Icons.pets_rounded, color: TinColors.coral)
                  : DogPortrait(dog: dog),
            ),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: TinColors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
