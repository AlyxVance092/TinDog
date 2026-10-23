import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../models/dog.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.repository,
    required this.onChat,
  });
  final TinDogRepository repository;
  final void Function(String id, String name) onChat;
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final _search = TextEditingController();
  String _query = '';
  bool _unreadOnly = false;
  @override
  void initState() {
    super.initState();
    _future = widget.repository.matches();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 9, 18, 4),
    child: Column(
      children: [
        PageHeading(
          'Mensajes',
          subtitle: 'Conoce a sus familias.',
          trailing: const _ChatHeadingBadge(),
        ),
        const SizedBox(height: 13),
        const _ChatIntroCard(),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: InputDecoration(
            hintText: 'Buscar una conversación',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: .055)
                : Colors.white.withValues(alpha: .78),
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Text(
                'Tus conversaciones',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
            FilterChip(
              avatar: Icon(
                Icons.mark_chat_unread_rounded,
                size: 15,
                color: _unreadOnly ? Colors.white : TinColors.coral,
              ),
              label: const Text('No leídos'),
              selected: _unreadOnly,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: _unreadOnly ? Colors.white : null,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
              selectedColor: TinColors.coral,
              onSelected: (value) => setState(() => _unreadOnly = value),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return ListView.separated(
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, _) =>
                      const SkeletonCard(height: 76, radius: 18),
                );
              }
              final query = _query.toLowerCase();
              final rows = (snapshot.data ?? [])
                  .where((row) {
                    final matchesQuery =
                        query.isEmpty ||
                        (row['name'] as String? ?? '').toLowerCase().contains(
                          query,
                        ) ||
                        (row['lastMessage'] as String? ?? '')
                            .toLowerCase()
                            .contains(query);
                    final unread = (row['unread'] as int? ?? 0) > 0;
                    return matchesQuery && (!_unreadOnly || unread);
                  })
                  .toList(growable: false);
              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    'Cuando tengas un match, sus mensajes aparecerán aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final dogId = row['dogId'] as String;
                  final name = row['name'] as String? ?? 'Match';
                  final unread = row['unread'] as int? ?? 0;
                  return StaggeredIn(
                    index: index,
                    child: PressScale(
                      onTap: () => widget.onChat(dogId, name),
                      child: GlassCard(
                        radius: 21,
                        color: unread > 0
                            ? TinColors.coral.withValues(
                                alpha:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? .11
                                    : .055,
                              )
                            : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            _MiniAvatar(
                              repository: widget.repository,
                              id: dogId,
                              size: 55,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (unread == 0)
                                        const Icon(
                                          Icons.done_all_rounded,
                                          size: 14,
                                          color: TinColors.green,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    row['lastMessage'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Theme.of(context).hintColor,
                                      fontWeight: unread > 0
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.verified_rounded,
                                        size: 12,
                                        color: TinColors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Familia verificada',
                                        style: TextStyle(
                                          color: Theme.of(context).hintColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  row['time'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: unread > 0
                                        ? TinColors.coral
                                        : Theme.of(context).hintColor,
                                    fontWeight: unread > 0
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                if (unread > 0)
                                  Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 21,
                                      minHeight: 21,
                                    ),
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: TinColors.coral,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$unread',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

class _ChatHeadingBadge extends StatelessWidget {
  const _ChatHeadingBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: TinColors.coral.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_rounded, size: 13, color: TinColors.coral),
        SizedBox(width: 5),
        Text(
          'CHAT',
          style: TextStyle(
            color: TinColors.coral,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      ],
    ),
  );
}

class _ChatIntroCard extends StatelessWidget {
  const _ChatIntroCard();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(21),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? const [Color(0xFF55342E), Color(0xFF332620)]
              : const [Color(0xFFF2553A), Color(0xFFFA8662)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: TinColors.coral.withValues(alpha: .2),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: -17,
            child: Icon(
              Icons.pets_rounded,
              size: 84,
              color: Colors.white.withValues(alpha: .09),
            ),
          ),
          const Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x33FFFFFF),
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conexiones con patas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Coordinen su próximo encuentro.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 19),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({
    required this.repository,
    required this.id,
    this.size = 48,
  });
  final TinDogRepository repository;
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) => FutureBuilder<Dog?>(
    future: repository.dogById(id),
    builder: (_, snap) => SizedBox(
      width: size,
      height: size,
      child: Hero(
        tag: 'chat-dog-$id',
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: TinColors.peach,
          ),
          child: snap.data == null
              ? const Icon(Icons.pets, color: TinColors.coral)
              : DogPortrait(dog: snap.data!),
        ),
      ),
    ),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.repository,
    required this.dogId,
    required this.name,
  });
  final TinDogRepository repository;
  final String dogId;
  final String name;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late Future<List<ChatMessage>> _future;
  List<ChatMessage> _messages = [];
  bool _typing = false;
  Timer? _replyTimer;
  @override
  void initState() {
    super.initState();
    _future = widget.repository.messages(widget.dogId);
  }

  @override
  void dispose() {
    _replyTimer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    _controller.clear();
    final message = ChatMessage(
      text: text,
      mine: true,
      time: _time(),
      read: false,
    );
    await widget.repository.sendMessage(widget.dogId, message);
    if (!mounted) return;
    setState(() {
      _messages.add(message);
      _typing = true;
    });
    _toBottom();
    _replyTimer?.cancel();
    _replyTimer = Timer(const Duration(milliseconds: 2300), () async {
      const reply = ChatMessage(
        text: '¡Qué gusto! A nosotros también nos emociona conocernos 🐾',
        mine: false,
        time: 'Ahora',
      );
      await widget.repository.sendMessage(widget.dogId, reply);
      if (mounted) {
        setState(() {
          _typing = false;
          _messages.add(reply);
        });
        _toBottom();
      }
    });
  }

  Future<void> _clearConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_rounded, color: TinColors.coral),
        title: const Text('Vaciar conversación?'),
        content: const Text(
          'Se borrarán los mensajes guardados en este dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('Vaciar'),
            style: FilledButton.styleFrom(backgroundColor: TinColors.coral),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _replyTimer?.cancel();
    await widget.repository.clearConversation(widget.dogId);
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _typing = false;
      _future = Future.value(const <ChatMessage>[]);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Conversación vaciada.')));
  }

  String _time() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Duration(milliseconds: motionReduced ? 0 : 260),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 15, 10),
            child: GlassCard(
              radius: 23,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: TinColors.coral.withValues(alpha: .09),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  _MiniAvatar(repository: widget.repository, id: widget.dogId),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.circle, size: 7, color: TinColors.green),
                            SizedBox(width: 5),
                            Text(
                              'Match verificado',
                              style: TextStyle(
                                color: TinColors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones de chat',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (value) {
                      if (value == 'clear') _clearConversation();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'clear',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep_rounded, size: 19),
                            SizedBox(width: 9),
                            Text('Vaciar conversación'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: TinColors.green.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded, size: 12, color: TinColors.green),
                  SizedBox(width: 5),
                  Text(
                    'Conversación entre familias verificadas',
                    style: TextStyle(
                      color: TinColors.green,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ChatMessage>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonCard(height: 330),
                  );
                }
                if (_messages.isEmpty) _messages = snapshot.data ?? [];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
                  controller: _scroll,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: TinColors.peach.withValues(alpha: .58),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Hoy',
                          style: TextStyle(
                            color: TinColors.ink,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_messages.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Column(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: TinColors.coral.withValues(alpha: .1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.waving_hand_rounded,
                                size: 32,
                                color: TinColors.coral,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Aún no hay mensajes. ¡Saluda primero!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 7,
                              children: ['¡Hola! 🐾', '¿Cómo está? 😊']
                                  .map(
                                    (reply) => ActionChip(
                                      label: Text(reply),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        _controller.text = reply;
                                        _controller.selection =
                                            TextSelection.collapsed(
                                              offset: reply.length,
                                            );
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ..._messages.asMap().entries.map(
                      (entry) => _MessageBubble(
                        message: entry.value,
                        index: entry.key,
                      ),
                    ),
                    if (_typing) const _TypingDots(),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      prefixIcon: IconButton(
                        tooltip: 'Agregar una patita',
                        onPressed: () {
                          final text = _controller.text;
                          _controller.text = '$text 🐾';
                          _controller.selection = TextSelection.collapsed(
                            offset: _controller.text.length,
                          );
                        },
                        icon: const Icon(
                          Icons.pets_rounded,
                          color: TinColors.coral,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? TinColors.darkCard
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PressScale(
                  onTap: _send,
                  child: Container(
                    width: 49,
                    height: 49,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [TinColors.coral, Color(0xFFFF795D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TinColors.coral.withValues(alpha: .3),
                          blurRadius: 13,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.index});
  final ChatMessage message;
  final int index;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(15, 11, 15, 9),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .77,
      ),
      decoration: BoxDecoration(
        color: message.mine
            ? null
            : (Theme.of(context).brightness == Brightness.dark
                  ? TinColors.darkCard
                  : Colors.white),
        gradient: message.mine
            ? const LinearGradient(
                colors: [TinColors.coral, Color(0xFFFA7558)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(17),
          topRight: const Radius.circular(17),
          bottomLeft: Radius.circular(message.mine ? 17 : 5),
          bottomRight: Radius.circular(message.mine ? 5 : 17),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .045),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: message.mine
            ? null
            : Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: .08),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            message.text,
            style: TextStyle(
              color: message.mine
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.time,
                style: TextStyle(
                  fontSize: 9,
                  color: message.mine
                      ? Colors.white70
                      : Theme.of(context).hintColor,
                ),
              ),
              if (message.mine) ...[
                const SizedBox(width: 4),
                _DoubleCheck(read: message.read),
              ],
            ],
          ),
        ],
      ),
    );
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: motionReduced ? 0 : 360),
        curve: Curves.easeOutCubic,
        builder: (_, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset((message.mine ? 16 : -16) * (1 - value), 0),
            child: child,
          ),
        ),
        child: bubble,
      ),
    );
  }
}

class _DoubleCheck extends StatelessWidget {
  const _DoubleCheck({required this.read});
  final bool read;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: read ? 1 : .25),
    duration: Duration(milliseconds: motionReduced ? 0 : 650),
    builder: (_, value, _) => Icon(
      Icons.done_all_rounded,
      size: 14,
      color: Color.lerp(Colors.white54, const Color(0xFFB4F6DC), value),
    ),
  );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..repeat();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? TinColors.darkCard
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (index) => AnimatedBuilder(
            animation: _controller,
            builder: (_, _) {
              final phase = (_controller.value - index * .2).abs();
              final bump = motionReduced
                  ? 0.0
                  : 1 - (phase > .5 ? 1 - phase : phase) * 1.4;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Transform.translate(
                  offset: Offset(0, -4 * bump),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: TinColors.coral,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
