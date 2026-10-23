import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/dog.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DogDetailScreen extends StatefulWidget {
  const DogDetailScreen({
    super.key,
    required this.dog,
    required this.repository,
  });
  final Dog dog;
  final TinDogRepository repository;
  @override
  State<DogDetailScreen> createState() => _DogDetailScreenState();
}

class _DogDetailScreenState extends State<DogDetailScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _healthKey = GlobalKey();
  double _offset = 0;
  bool _requested = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _offset = _scroll.offset));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dog = widget.dog;
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 410,
            stretch: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(
                    offset: Offset(0, _offset * .18),
                    child: Hero(
                      tag: 'dog-${dog.id}',
                      child: DogPortrait(dog: dog),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x44000000),
                          Colors.transparent,
                          Color(0xA6000000),
                        ],
                        stops: [0, .48, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: 24,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${dog.name}, ${dog.age}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Bricolage Grotesque',
                            fontWeight: FontWeight.w900,
                            fontSize: 33,
                            letterSpacing: -.7,
                            shadows: [
                              Shadow(color: Colors.black38, blurRadius: 12),
                            ],
                          ),
                        ),
                        Text(
                          dog.breed,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${dog.location} · ${dog.distanceKm} km de ti',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Perfil guardado en tus favoritos'),
                  ),
                ),
                icon: const Icon(Icons.bookmark_border_rounded),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 19, 18, 105),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Un poco sobre mí',
                        style: TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    VerifiedPill(),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  dog.about,
                  style: TextStyle(
                    height: 1.55,
                    color: Theme.of(context).hintColor,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 18),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Compatibilidad',
                              style: TextStyle(
                                fontFamily: 'Bricolage Grotesque',
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color,
                              ),
                            ),
                          ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: dog.compatibility.toDouble(),
                            ),
                            duration: Duration(
                              milliseconds: motionReduced ? 0 : 950,
                            ),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, _) => Text(
                              '${value.round()}%',
                              style: const TextStyle(
                                color: TinColors.coral,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: dog.compatibility / 100),
                          duration: Duration(
                            milliseconds: motionReduced ? 0 : 1000,
                          ),
                          builder: (_, value, _) => LinearProgressIndicator(
                            minHeight: 9,
                            value: value,
                            backgroundColor: TinColors.peach.withValues(
                              alpha: .55,
                            ),
                            color: TinColors.coral,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Coinciden en raza, edad y estilo de vida.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Salud y vacunas',
                  key: _healthKey,
                  style: TextStyle(
                    fontFamily: 'Bricolage Grotesque',
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 10),
                ...dog.vaccines.entries.toList().asMap().entries.map(
                  (entry) => _VaccineRow(
                    index: entry.key,
                    name: entry.value.key,
                    date: entry.value.value,
                  ),
                ),
                const SizedBox(height: 15),
                GlassCard(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: TinColors.green.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: TinColors.green,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dog.pedigree
                                  ? 'Pedigrí registrado'
                                  : 'Sin pedigrí',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dog.pedigree ? dog.pedigreeNumber : 'Este perfil cuenta con vacunas verificadas',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dog.pedigree)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: TinColors.green,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final target = _healthKey.currentContext;
                      if (target != null) {
                        Scrollable.ensureVisible(
                          target,
                          duration: Duration(
                            milliseconds: motionReduced ? 0 : 420,
                          ),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    icon: const Icon(Icons.vaccines_rounded),
                    label: const Text('Vacunas'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TinColors.coral,
                      side: const BorderSide(color: TinColors.coral),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: _requested ? 'Solicitud enviada' : 'Enviar solicitud',
                  icon: _requested
                      ? Icons.check_rounded
                      : Icons.favorite_rounded,
                  onPressed: _requested
                      ? null
                      : () async {
                          await widget.repository.sendRequest(dog);
                          if (!context.mounted) return;
                          setState(() => _requested = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Solicitud guardada. ¡Te avisaremos si aceptan!',
                              ),
                            ),
                          );
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaccineRow extends StatelessWidget {
  const _VaccineRow({
    required this.index,
    required this.name,
    required this.date,
  });
  final int index;
  final String name;
  final String date;
  @override
  Widget build(BuildContext context) => StaggeredIn(
    index: index,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 17,
        child: Row(
          children: [
            Container(
              width: 33,
              height: 33,
              decoration: BoxDecoration(
                color: TinColors.green.withValues(alpha: .13),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: TinColors.green,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Vigente hasta $date',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(
                milliseconds: motionReduced ? 0 : 650 + index * 260,
              ),
              builder: (_, v, _) => SizedBox(
                width: 46,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 5,
                    color: TinColors.green,
                    backgroundColor: TinColors.green.withValues(alpha: .12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
