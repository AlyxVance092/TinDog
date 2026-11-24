import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../data/repository.dart';
import '../models/dog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dog_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.repository,
    required this.onChat,
    this.active = true,
  });
  final TinDogRepository repository;
  final void Function(String dogId, String name) onChat;
  final bool active;
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late Future<List<Dog>> _future;
  List<Dog> _dogs = [];
  List<Dog> _myDogs = [];
  String? _selectedDogId;
  int _index = 0;
  Offset _drag = Offset.zero;
  Offset _tilt = Offset.zero;
  StreamSubscription<GyroscopeEvent>? _sensor;
  Timer? _particleTimer;
  Timer? _activityTimer;
  int _particleId = 0;
  bool _showParticles = false;
  bool _particleLike = false;
  bool _particleSuperLike = false;
  bool _swiping = false;
  String _activityLabel = 'MANADA CERCA';
  bool _activitySuccess = false;
  DateTime _lastSensorFrame = DateTime.fromMillisecondsSinceEpoch(0);
  int _distance = 100;
  String _sex = 'Todos';

  @override
  void initState() {
    super.initState();
    _future = _loadDogs(refreshLocation: true);
    if (widget.active) _startSensor();
  }

  @override
  void didUpdateWidget(covariant DiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _startSensor();
    } else {
      _stopSensor();
      _tilt = Offset.zero;
    }
  }

  void _startSensor() {
    if (_sensor != null || motionReduced) return;
    try {
      _sensor = gyroscopeEventStream().listen((event) {
        if (!mounted || !widget.active || motionReduced) return;
        final now = DateTime.now();
        if (now.difference(_lastSensorFrame).inMilliseconds < 24) return;
        _lastSensorFrame = now;
        setState(
          () => _tilt = Offset(
            (event.y / 4).clamp(-.8, .8),
            (event.x / 4).clamp(-.6, .6),
          ),
        );
      }, onError: (_) {});
    } catch (_) {
      // Drag gestures remain as the fallback when no orientation sensor exists.
    }
  }

  void _stopSensor() {
    _sensor?.cancel();
    _sensor = null;
  }

  Future<List<Dog>> _loadDogs({bool refreshLocation = false}) async {
    if (refreshLocation && widget.repository.supportsDistanceFilter) {
      await widget.repository.refreshDeviceLocation();
    }
    final savedDistance = await widget.repository.discoveryDistanceKm();
    if (mounted) setState(() => _distance = savedDistance);
    final myDogs = await widget.repository.myDogs();
    if (myDogs.isEmpty) {
      throw StateError('Registra un perro antes de buscar candidatos.');
    }
    var selectedDogId = _selectedDogId;
    if (selectedDogId == null ||
        !myDogs.any((dog) => dog.id == selectedDogId)) {
      selectedDogId = myDogs.first.id;
    }
    if (mounted) {
      setState(() {
        _myDogs = myDogs;
        _selectedDogId = selectedDogId;
      });
    }
    final allDogs = await widget.repository.discoverDogs(
      sourceDogId: selectedDogId,
    );
    final filtered = allDogs
        .where((dog) => _sex == 'Todos' || dog.sex == _sex)
        .toList();
    if (mounted) setState(() => _dogs = filtered);
    return allDogs;
  }

  @override
  void dispose() {
    _stopSensor();
    _particleTimer?.cancel();
    _activityTimer?.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _index = 0;
    _dogs = [];
    _future = _loadDogs(refreshLocation: true);
  });

  Future<void> _replayManada() async {
    await widget.repository.resetDiscovery();
    if (mounted) _reload();
  }

  Future<void> _swipe(bool liked, {bool superLike = false}) async {
    if (_swiping || _index >= _dogs.length) return;
    _swiping = true;
    final dog = _dogs[_index];
    final particleId = ++_particleId;
    _particleTimer?.cancel();
    _activityTimer?.cancel();
    if (superLike) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _drag = Offset(liked ? 500 : -500, _drag.dy * 1.2);
      _showParticles = true;
      _particleLike = liked;
      _particleSuperLike = superLike;
      _activitySuccess = liked;
      _activityLabel = superLike
          ? 'ESTRELLA PARA ${dog.name.toUpperCase()}'
          : liked
          ? 'INTERÉS EN ${dog.name.toUpperCase()}'
          : 'SIGUIENDO';
    });
    _particleTimer = Timer(const Duration(milliseconds: 620), () {
      if (mounted && particleId == _particleId) {
        setState(() => _showParticles = false);
      }
    });
    _activityTimer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted) {
        setState(() {
          _activityLabel = 'MANADA CERCA';
          _activitySuccess = false;
        });
      }
    });
    await Future<void>.delayed(Duration(milliseconds: motionReduced ? 0 : 260));
    String? swipeResult;
    try {
      swipeResult = await widget.repository.swipe(
        dog.id,
        sourceDogId: dog.sourceDogId,
        liked: liked,
        superLike: superLike,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _drag = Offset.zero;
        _tilt = Offset.zero;
        _swiping = false;
        _showParticles = false;
        _activitySuccess = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos guardar el deslizamiento.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _index++;
      _drag = Offset.zero;
      _tilt = Offset.zero;
      _swiping = false;
    });
    if (_index >= _dogs.length) _reload();
    if (swipeResult == 'match') {
      final ownDogs = await widget.repository.myDogs();
      if (!mounted || ownDogs.isEmpty) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => MatchCelebration(
          dog: dog,
          myDog: ownDogs.firstWhere(
            (mine) => mine.id == dog.sourceDogId,
            orElse: () => ownDogs.first,
          ),
          onChat: () {
            Navigator.pop(dialogContext);
            widget.onChat(dog.id, dog.name);
          },
        ),
      );
    }
  }

  Future<void> _openDogDetail(Dog dog) async {
    _stopSensor();
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DogDetailScreen(dog: dog, repository: widget.repository),
        ),
      );
    } finally {
      if (mounted && widget.active) _startSensor();
    }
  }

  Future<void> _chooseSourceDog() async {
    List<Dog> currentDogs;
    try {
      currentDogs = await widget.repository.myDogs();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pudimos cargar tus perros: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _myDogs = currentDogs;
      if (!_myDogs.any((dog) => dog.id == _selectedDogId)) {
        _selectedDogId = _myDogs.isEmpty ? null : _myDogs.first.id;
      }
    });
    if (_myDogs.length < 2) {
      if (_myDogs.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primero registra un perfil de perro.')),
        );
      }
      return;
    }
    final chosenDog = await showModalBottomSheet<Dog>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                '¿Con cuál perro quieres buscar?',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
            ),
            ..._myDogs.map(
              (dog) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: TinColors.peach,
                  child: const Icon(Icons.pets_rounded, color: TinColors.coral),
                ),
                title: Text(dog.name),
                subtitle: Text(dog.breed),
                trailing: dog.id == _selectedDogId
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: TinColors.green,
                      )
                    : null,
                onTap: () => Navigator.pop(sheetContext, dog),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosenDog == null || chosenDog.id == _selectedDogId || !mounted) return;
    setState(() {
      _selectedDogId = chosenDog.id;
      _index = 0;
      _drag = Offset.zero;
      _dogs = [];
      _future = _loadDogs();
    });
  }

  Future<void> _filters() async {
    var distance = _distance.toDouble();
    var sex = _sex;
    final result = await showModalBottomSheet<_FilterPrefs>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: TinColors.ink.withValues(alpha: .26),
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => SafeArea(
          top: false,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: motionReduced ? 0 : 22,
                sigmaY: motionReduced ? 0 : 22,
              ),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  22,
                  10,
                  22,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? TinColors.dark.withValues(alpha: .88)
                      : Colors.white.withValues(alpha: .78),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? .12
                          : .72,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).hintColor
                              .withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    PageHeading(
                      'Filtros',
                      subtitle: 'Encuentra perfiles que hacen match',
                    ),
                    const SizedBox(height: 23),
                    if (widget.repository.supportsDistanceFilter) ...[
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Distancia máxima',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${distance.round()} km',
                            style: const TextStyle(
                              color: TinColors.coral,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: distance,
                        min: 5,
                        max: 100,
                        divisions: 19,
                        activeColor: TinColors.coral,
                        onChanged: (v) => setModal(() => distance = v),
                        onChangeEnd: (_) => HapticFeedback.selectionClick(),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const Text(
                      'Buscar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['Todos', 'Hembra', 'Macho']
                          .map(
                            (value) => ChoiceChip(
                              label: Text(value),
                              selected: sex == value,
                              labelStyle: TextStyle(
                                color: sex == value ? TinColors.coral : null,
                                fontWeight: FontWeight.w700,
                              ),
                              selectedColor: TinColors.peach,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setModal(() => sex = value);
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 9),
                    PrimaryButton(
                      label: 'Ver perfiles',
                      onPressed: () => Navigator.pop(
                        context,
                        _FilterPrefs(distance.round(), sex),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      try {
        await widget.repository.updateDiscoveryDistanceKm(result.distance);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo guardar el radio de búsqueda: $error'),
            ),
          );
        }
        return;
      }
      setState(() {
        _distance = result.distance;
        _sex = result.sex;
        _index = 0;
        _dogs = [];
        _future = _loadDogs();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 700;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 1),
      child: Column(
        children: [
          PageHeading('Descubre', subtitle: 'Conexiones sanas, de verdad.'),
          const SizedBox(height: 9),
          Row(
            children: [
              _LiveActivityIsland(
                label: _activityLabel,
                success: _activitySuccess,
              ),
              const Spacer(),
              PressScale(
                onTap: _filters,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: TinColors.peach.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: TinColors.coral,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
          if (_myDogs.isNotEmpty) ...[
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _chooseSourceDog,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: TinColors.coral.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: TinColors.coral.withValues(alpha: .16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.pets_rounded,
                        size: 14,
                        color: TinColors.coral,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Buscando con ${_myDogs.firstWhere((dog) => dog.id == _selectedDogId, orElse: () => _myDogs.first).name}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_myDogs.length > 1) ...[
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 17,
                          color: TinColors.coral,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 9),
          if (!compact)
            GlassCard(
              radius: 15,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    size: 15,
                    color: TinColors.green,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'VACUNAS Y PERFILES VERIFICADOS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: TinColors.green,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .55,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: motionReduced ? 0 : 240),
                    child: Text(
                      _dogs.isEmpty
                          ? 'BASE ACTIVA'
                          : '${math.max(0, _dogs.length - _index)} PERFILES',
                      key: ValueKey('${_dogs.length}-$_index'),
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!compact) const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Dog>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SkeletonCard();
                }
                if (snapshot.hasError) {
                  return _empty(
                    snapshot.error is StateError
                        ? (snapshot.error as StateError).message.toString()
                        : 'No pudimos cargar los candidatos.',
                    Icons.wifi_off_rounded,
                    _reload,
                  );
                }
                if (_dogs.isEmpty || _index >= _dogs.length) {
                  return _empty(
                    widget.repository.canReplayDiscovery
                        ? '¡Ya viste a toda la manada!'
                        : 'Supabase devolvió 0 candidatos. Se excluyen perfiles fuera del radio, ocultos, con intención incompatible o ya deslizados. Revisa esos filtros y busca de nuevo.',
                    Icons.pets_rounded,
                    widget.repository.canReplayDiscovery
                        ? _replayManada
                        : _reload,
                    button: widget.repository.canReplayDiscovery
                        ? 'Volver a ver perfiles'
                        : 'Buscar de nuevo',
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final height = constraints.maxHeight;
                    final width = math.min(
                      constraints.maxWidth - 16,
                      height * .77,
                    );
                    return Center(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            if (!motionReduced) ...[
                              Positioned(
                                left: -8,
                                top: 84,
                                child: _ColorBloom(
                                  color: _dogs[_index].dominantColor,
                                  diameter: 48,
                                  offset: _tilt.dx * 3,
                                ),
                              ),
                              Positioned(
                                right: -10,
                                bottom: 82,
                                child: _ColorBloom(
                                  color: _dogs[_index].dominantColor,
                                  diameter: 59,
                                  offset: -_tilt.dx * 2.5,
                                ),
                              ),
                            ],
                            if (_index + 1 < _dogs.length)
                              Positioned.fill(
                                child: Transform.translate(
                                  offset: Offset.zero.translate(0, 9),
                                  child: Transform.scale(
                                    scale: .965,
                                    child: _DogCard(
                                      dog: _dogs[_index + 1],
                                      drag: Offset.zero,
                                      tilt: Offset.zero,
                                      onTap: null,
                                      gesture: false,
                                    ),
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: _DogCard(
                                dog: _dogs[_index],
                                drag: _drag,
                                tilt: _tilt,
                                gesture: true,
                                onTap: () => _openDogDetail(_dogs[_index]),
                                onDrag: (delta) =>
                                    setState(() => _drag += delta),
                                onEnd: () {
                                  if (_drag.dx > 85) {
                                    _swipe(true);
                                  } else if (_drag.dx < -85) {
                                    _swipe(false);
                                  } else {
                                    setState(() => _drag = Offset.zero);
                                  }
                                },
                              ),
                            ),
                            if (_showParticles)
                              Positioned.fill(
                                child: _SwipeParticleBurst(
                                  key: ValueKey(_particleId),
                                  liked: _particleLike,
                                  superLike: _particleSuperLike,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          GlassCard(
            radius: 25,
            padding: EdgeInsets.fromLTRB(
              12,
              compact ? 6 : 8,
              12,
              compact ? 6 : 8,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SwipeAction(
                      icon: Icons.close_rounded,
                      label: 'PASAR',
                      color: const Color(0xFFE96F64),
                      size: compact ? 43 : 48,
                      compact: compact,
                      onTap: () => _swipe(false),
                    ),
                    _SwipeAction(
                      icon: Icons.favorite_rounded,
                      label: 'ME GUSTA',
                      color: TinColors.green,
                      size: compact ? 52 : 58,
                      compact: compact,
                      onTap: () => _swipe(true),
                    ),
                    _SwipeAction(
                      icon: Icons.star_rounded,
                      label: 'ESTRELLA',
                      color: const Color(0xFFE8A746),
                      size: compact ? 43 : 48,
                      compact: compact,
                      onTap: () => _swipe(true, superLike: true),
                    ),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Desliza la tarjeta para decidir',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 3),
        ],
      ),
    );
  }

  Widget _empty(
    String message,
    IconData icon,
    VoidCallback? retry, {
    String button = 'Intentar de nuevo',
  }) => Center(
    child: GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 39, color: TinColors.coral),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          if (retry != null) ...[
            const SizedBox(height: 14),
            PressScale(
              onTap: retry,
              child: Text(
                button,
                style: const TextStyle(
                  color: TinColors.coral,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _FilterPrefs {
  const _FilterPrefs(this.distance, this.sex);
  final int distance;
  final String sex;
}

class _LiveActivityIsland extends StatefulWidget {
  const _LiveActivityIsland({required this.label, required this.success});
  final String label;
  final bool success;

  @override
  State<_LiveActivityIsland> createState() => _LiveActivityIslandState();
}

class _LiveActivityIslandState extends State<_LiveActivityIsland>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    if (!motionReduced) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = widget.success ? TinColors.green : TinColors.coral;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final pulse = motionReduced ? 0 : _pulse.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: motionReduced ? 0 : 13,
              sigmaY: motionReduced ? 0 : 13,
            ),
            child: AnimatedContainer(
              duration: Duration(milliseconds: motionReduced ? 0 : 380),
              curve: Curves.easeOutBack,
              constraints: const BoxConstraints(maxWidth: 238),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: (dark ? TinColors.darkCard : Colors.white).withValues(
                  alpha: dark ? .76 : .74,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: tint.withValues(alpha: .15 + pulse * .18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: tint.withValues(alpha: .07 + pulse * .08),
                    blurRadius: 16 + pulse * 5,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 1 + pulse * .12,
                    child: Icon(
                      widget.success
                          ? Icons.favorite_rounded
                          : Icons.pets_rounded,
                      size: 15,
                      color: tint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: motionReduced ? 0 : 210),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .25),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        widget.label,
                        key: ValueKey(widget.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: dark ? Colors.white : TinColors.ink,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .55,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tint,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tint.withValues(alpha: .48),
                          blurRadius: 6 + pulse * 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SwipeParticleBurst extends StatefulWidget {
  const _SwipeParticleBurst({
    super.key,
    required this.liked,
    required this.superLike,
  });
  final bool liked;
  final bool superLike;

  @override
  State<_SwipeParticleBurst> createState() => _SwipeParticleBurstState();
}

class _SwipeParticleBurstState extends State<_SwipeParticleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: motionReduced ? 1 : 570),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final progress = Curves.easeInBack.transform(_controller.value);
          final centerX = constraints.maxWidth / 2;
          final centerY = constraints.maxHeight / 2;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < 16; i++)
                _particle(i, centerX, centerY, constraints.maxWidth, progress),
            ],
          );
        },
      ),
    ),
  );

  Widget _particle(
    int index,
    double centerX,
    double centerY,
    double width,
    double progress,
  ) {
    final angle = index / 16 * math.pi * 2;
    final startX = centerX + math.cos(angle) * width * .38;
    final startY = centerY + math.sin(angle) * width * .31;
    final endX = widget.liked ? centerX : -width * .24;
    final endY = widget.liked ? centerY : startY + math.sin(angle) * 60;
    final x = startX + (endX - startX) * progress;
    final y = startY + (endY - startY) * progress;
    final opacity = (1 - progress).clamp(0.0, 1.0);
    final color = widget.superLike
        ? const Color(0xFFFFC857)
        : widget.liked
        ? (index.isEven ? TinColors.coral : TinColors.peach)
        : const Color(0xFFE96F64);
    final icon = widget.superLike
        ? Icons.star_rounded
        : index % 4 == 0
        ? Icons.auto_awesome_rounded
        : widget.liked
        ? Icons.favorite_rounded
        : Icons.pets_rounded;
    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: progress * (index.isEven ? 2.1 : -2.1),
          child: Icon(
            icon,
            size: 10 + (index % 3) * 4,
            color: color,
            shadows: const [Shadow(color: Colors.black26, blurRadius: 7)],
          ),
        ),
      ),
    );
  }
}

class _ColorBloom extends StatelessWidget {
  const _ColorBloom({
    required this.color,
    required this.diameter,
    required this.offset,
  });
  final Color color;
  final double diameter;
  final double offset;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(offset, 0),
    child: Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .33),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .56),
            blurRadius: 25,
            spreadRadius: 4,
          ),
        ],
      ),
    ),
  );
}

class _SwipeAction extends StatefulWidget {
  const _SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.size,
    required this.compact,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_SwipeAction> createState() => _SwipeActionState();
}

class _SwipeActionState extends State<_SwipeAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _impact = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 430),
  );

  @override
  void dispose() {
    _impact.dispose();
    super.dispose();
  }

  void _activate() {
    if (!motionReduced) _impact.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: _activate,
    child: AnimatedBuilder(
      animation: _impact,
      builder: (context, _) {
        final progress = _impact.value;
        final bounce = math.sin(progress * math.pi);
        final themeDark = Theme.of(context).brightness == Brightness.dark;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.size + 12,
              height: widget.size + 12,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!motionReduced && progress > 0)
                    Transform.scale(
                      scale: 1 + progress * .48,
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.color.withValues(
                              alpha: (1 - progress) * .43,
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  Transform.scale(
                    scale: 1 + bounce * .14,
                    child: Transform.rotate(
                      angle: widget.icon == Icons.star_rounded
                          ? -.16 * bounce
                          : widget.icon == Icons.close_rounded
                          ? .12 * bounce
                          : 0,
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: themeDark
                                ? [
                                    TinColors.darkCard,
                                    widget.color.withValues(alpha: .13),
                                  ]
                                : [
                                    Colors.white,
                                    widget.color.withValues(alpha: .09),
                                  ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.color.withValues(alpha: .16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withValues(
                                alpha: .16 + bounce * .24,
                              ),
                              blurRadius: 17 + bounce * 10,
                              spreadRadius: bounce * 2,
                              offset: Offset(0, 6 + bounce * 3),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(
                                alpha: themeDark ? .035 : .78,
                              ),
                              blurRadius: 3,
                              offset: const Offset(-3, -3),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.color,
                          size: widget.size * .43,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.compact) ...[
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .45,
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _DogCard extends StatelessWidget {
  const _DogCard({
    required this.dog,
    required this.drag,
    required this.tilt,
    required this.gesture,
    this.onTap,
    this.onDrag,
    this.onEnd,
  });
  final Dog dog;
  final Offset drag;
  final Offset tilt;
  final bool gesture;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onDrag;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final displayDrag = drag + Offset(tilt.dx * 12, tilt.dy * 8);
    final radians = (drag.dx / 640).clamp(-.25, .25) + tilt.dx * .09;
    final compatibility = dog.compatibility ?? 0;
    final rarityColor = compatibility >= 95
        ? const Color(0xFFFFC857)
        : compatibility >= 85
        ? TinColors.coral
        : TinColors.green;
    final card = Hero(
      tag: 'dog-${dog.id}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              color: dog.dominantColor.withValues(alpha: .42),
            ),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(-tilt.dx * 10, -tilt.dy * 8),
                child: Transform.scale(
                  scale: 1.04,
                  child: DogPortrait(dog: dog),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x23000000),
                      Colors.transparent,
                      Color(0x05000000),
                      Color(0xD9000000),
                    ],
                    stops: [0, .17, .51, 1],
                  ),
                ),
              ),
            ),
            if (!motionReduced)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(
                          -.65 + (drag.dx / 700).clamp(-.8, .8),
                          -.6 + (drag.dy / 700).clamp(-.5, .5),
                        ),
                        radius: .9,
                        colors: [
                          Colors.white.withValues(alpha: .26),
                          Colors.white.withValues(alpha: .04),
                          Colors.transparent,
                        ],
                        stops: const [0, .26, .72],
                      ),
                    ),
                  ),
                ),
              ),
            if (dog.compatibility != null)
              Positioned(
                right: 14 + tilt.dx * 3,
                top: 14 + tilt.dy * 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        size: 15,
                        color: TinColors.coral,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${dog.compatibility}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: TinColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (drag.dx.abs() > 40)
              Positioned(
                left: drag.dx > 0 ? 22 : null,
                right: drag.dx < 0 ? 22 : null,
                top: 76,
                child: Transform.rotate(
                  angle: drag.dx > 0 ? -.17 : .17,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: drag.dx > 0 ? TinColors.green : TinColors.coral,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      drag.dx > 0 ? 'CRUZA' : 'PASO',
                      style: TextStyle(
                        color: drag.dx > 0 ? TinColors.green : TinColors.coral,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 19 + tilt.dx * 2,
              right: 19 + tilt.dx * 2,
              bottom: 19,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dog.compatibility != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .29),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: rarityColor.withValues(alpha: .7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: rarityColor,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            compatibility >= 95
                                ? 'QUÍMICA ESTELAR · ★★★★★'
                                : compatibility >= 85
                                ? 'MUY BUENA QUÍMICA · ★★★★'
                                : 'BUENA QUÍMICA · ★★★',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .35,
                              shadows: [
                                Shadow(
                                  color: rarityColor.withValues(alpha: .9),
                                  blurRadius: compatibility >= 95 ? 8 : 3,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    '${dog.name}, ${dog.age}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                      fontFamily: 'Bricolage Grotesque',
                      shadows: [Shadow(color: Colors.black38, blurRadius: 10)],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dog.breed,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        dog.distanceKm == null
                            ? dog.location
                            : '${dog.distanceKm} km · ${dog.location}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Positioned(
                right: 14,
                bottom: 122,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .3),
                    ),
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final transformed = Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, .001)
        ..rotateX(-displayDrag.dy * .00075)
        ..rotateY(displayDrag.dx * .0008)
        ..rotateZ(radians),
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(29),
          boxShadow: [
            BoxShadow(
              color: rarityColor.withValues(
                alpha: compatibility >= 95 ? .28 : .14,
              ),
              blurRadius: compatibility >= 95 ? 34 : 22,
              spreadRadius: compatibility >= 95 ? 1 : 0,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: card,
      ),
    );
    if (!gesture) return transformed;
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDrag?.call(details.delta),
      onPanEnd: (_) => onEnd?.call(),
      child: AnimatedContainer(
        duration: Duration(milliseconds: drag == Offset.zero ? 280 : 0),
        curve: Curves.easeOutBack,
        transform: Matrix4.translationValues(drag.dx, drag.dy, 0),
        child: transformed,
      ),
    );
  }
}

class MatchCelebration extends StatefulWidget {
  const MatchCelebration({
    super.key,
    required this.dog,
    required this.onChat,
    this.myDog,
  });
  final Dog dog;
  final Dog? myDog;
  final VoidCallback onChat;
  @override
  State<MatchCelebration> createState() => _MatchCelebrationState();
}

class _MatchCelebrationState extends State<MatchCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fall;
  int get _compatibility => widget.dog.compatibility ?? 0;

  @override
  void initState() {
    super.initState();
    _fall = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    if (!motionReduced) _fall.repeat();
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: SafeArea(
      child: Stack(
        children: [
          if (!motionReduced)
            ...List.generate(
              _compatibility >= 95 ? 30 : 18,
              (i) => AnimatedBuilder(
                animation: _fall,
                builder: (context, child) {
                  final y = (_fall.value + i * .071) % 1;
                  final x = .04 + ((i * 37) % 89) / 100;
                  return Positioned(
                    left: MediaQuery.sizeOf(context).width * x,
                    top: MediaQuery.sizeOf(context).height * y,
                    child: Transform.rotate(
                      angle: y * math.pi * 2,
                      child: Opacity(
                        opacity: .35 + .55 * math.sin(y * math.pi),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Icon(
                  _compatibility >= 95 && i % 3 == 0
                      ? Icons.star_rounded
                      : i.isEven
                      ? Icons.favorite_rounded
                      : Icons.pets_rounded,
                  size: i % 3 == 0 ? 23 : 16,
                  color: _compatibility >= 95 && i % 3 == 0
                      ? const Color(0xFFFFC857)
                      : i.isEven
                      ? TinColors.peach
                      : Colors.white,
                ),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '¡ES UN MATCH!',
                    style: TextStyle(
                      fontFamily: 'Bricolage Grotesque',
                      fontSize: 32,
                      letterSpacing: 1.1,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: _compatibility >= 95
                              ? const Color(0xFFFFC857)
                              : TinColors.coral,
                          blurRadius: _compatibility >= 95 ? 25 : 12,
                        ),
                      ],
                    ),
                  ),
                  if (_compatibility >= 95) ...[
                    const SizedBox(height: 7),
                    const Text(
                      'QUÍMICA ESTELAR · 5 ESTRELLAS',
                      style: TextStyle(
                        color: Color(0xFFFFD979),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  const Text(
                    'Dos familias, una gran historia por empezar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 31),
                  SizedBox(
                    height: 136,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!motionReduced)
                          AnimatedBuilder(
                            animation: _fall,
                            builder: (context, _) => Transform.scale(
                              scale:
                                  .94 +
                                  .08 * math.sin(_fall.value * math.pi * 2),
                              child: Container(
                                width: 128,
                                height: 128,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      (_compatibility >= 95
                                              ? const Color(0xFFFFC857)
                                              : TinColors.coral)
                                          .withValues(alpha: .4),
                                      TinColors.peach.withValues(alpha: .12),
                                      Colors.transparent,
                                    ],
                                    stops: const [0, .52, 1],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_compatibility >= 95
                                                  ? const Color(0xFFFFC857)
                                                  : TinColors.coral)
                                              .withValues(alpha: .42),
                                      blurRadius: 36,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 10,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: -1, end: 0),
                            duration: Duration(
                              milliseconds: motionReduced ? 0 : 650,
                            ),
                            curve: Curves.easeOutBack,
                            builder: (_, x, child) => Transform.translate(
                              offset: Offset(x * 40, 0),
                              child: child,
                            ),
                            child: _CirclePortrait(dog: widget.dog),
                          ),
                        ),
                        const Positioned(
                          child: Icon(
                            Icons.favorite_rounded,
                            color: TinColors.coral,
                            size: 39,
                          ),
                        ),
                        Positioned(
                          right: 10,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1, end: 0),
                            duration: Duration(
                              milliseconds: motionReduced ? 0 : 650,
                            ),
                            curve: Curves.easeOutBack,
                            builder: (_, x, child) => Transform.translate(
                              offset: Offset(x * 40, 0),
                              child: child,
                            ),
                            child: widget.myDog == null
                                ? const _MyDogPlaceholder()
                                : _CirclePortrait(dog: widget.myDog!),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.myDog == null
                        ? '${widget.dog.name} encontró una gran conexión'
                        : '${widget.dog.name} y ${widget.myDog!.name} se gustan',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 27),
                  SizedBox(
                    width: 270,
                    child: PrimaryButton(
                      label: 'Escribir a su familia',
                      icon: Icons.chat_bubble_rounded,
                      onPressed: widget.onChat,
                    ),
                  ),
                  const SizedBox(height: 13),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Seguir descubriendo',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 13,
            top: 6,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CirclePortrait extends StatelessWidget {
  const _CirclePortrait({required this.dog});
  final Dog dog;
  @override
  Widget build(BuildContext context) => Container(
    width: 90,
    height: 90,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5)),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: DogPortrait(dog: dog),
  );
}

class _MyDogPlaceholder extends StatelessWidget {
  const _MyDogPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    width: 90,
    height: 90,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [TinColors.peach, TinColors.coral],
      ),
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5)),
      ],
    ),
    child: const Icon(Icons.pets_rounded, color: Colors.white, size: 36),
  );
}
