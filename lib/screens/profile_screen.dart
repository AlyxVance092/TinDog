import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../models/dog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screens.dart';
import 'dog_wizard.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
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
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _signingOut = false;
  late Future<List<Dog>> _dogs;
  late Future<int> _dogCount;
  late Future<int> _matchCount;

  @override
  void initState() {
    super.initState();
    _dogs = widget.repository.myDogs();
    _dogCount = _dogs.then((dogs) => dogs.length);
    _matchCount = widget.repository.matches().then((matches) => matches.length);
  }

  void _refreshCountsAndDogs() {
    final dogs = widget.repository.myDogs();
    setState(() {
      _dogs = dogs;
      _dogCount = dogs.then((items) => items.length);
      _matchCount = widget.repository.matches().then((items) => items.length);
    });
  }

  Future<void> _addDog() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DogWizard(repository: widget.repository),
      ),
    );
    if (added == true && mounted) _refreshCountsAndDogs();
  }

  Future<void> _editDog(Dog dog) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DogWizard(repository: widget.repository, dog: dog),
      ),
    );
    if (updated == true && mounted) _refreshCountsAndDogs();
  }

  Future<void> _deleteDog(Dog dog) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: TinColors.coral),
        title: Text('Eliminar a ${dog.name}?'),
        content: const Text(
          'Se borrará su perfil y la foto guardada en este dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_rounded, size: 17),
            label: const Text('Eliminar'),
            style: FilledButton.styleFrom(backgroundColor: TinColors.coral),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteDog(dog.id);
    if (!mounted) return;
    _refreshCountsAndDogs();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Se eliminó el perfil de ${dog.name}.')),
    );
  }

  Future<void> _logout() async {
    if (_signingOut) return;
    HapticFeedback.mediumImpact();
    setState(() => _signingOut = true);
    var leavingProfile = false;
    try {
      await widget.repository.logout();
      if (!mounted) return;
      leavingProfile = true;
      unawaited(
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
          PageRouteBuilder<void>(
            transitionDuration: Duration(milliseconds: motionReduced ? 0 : 260),
            pageBuilder: (_, animation, _) => FadeTransition(
              opacity: animation,
              child: WelcomeScreen(
                repository: widget.repository,
                dark: widget.dark,
                onTheme: widget.onTheme,
              ),
            ),
          ),
          (_) => false,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos cerrar sesión. Intenta de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted && !leavingProfile) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.email.split('@').first;
    final name = widget.email == 'demo@tindog.mx'
        ? 'Familia Demo'
        : first
              .split(RegExp(r'[._-]'))
              .map(
                (word) => word.isEmpty
                    ? word
                    : '${word[0].toUpperCase()}${word.substring(1)}',
              )
              .join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 1),
      child: Column(
        children: [
          PageHeading(
            'Mi perfil',
            subtitle: 'Tu manada, tus reglas.',
            trailing: IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: _signingOut ? null : _logout,
              icon: _signingOut
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TinColors.coral,
                      ),
                    )
                  : const Icon(Icons.logout_rounded, color: TinColors.coral),
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            radius: 25,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: TinColors.peach,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: TinColors.coral,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.email,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: TinColors.green.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        color: TinColors.green,
                        size: 13,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Verificado',
                        style: TextStyle(
                          color: TinColors.green,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.pets_rounded,
                  count: _dogCount,
                  label: 'perros',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.favorite_rounded,
                  count: _matchCount,
                  label: 'matches',
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: _StatTile(
                  icon: Icons.shield_rounded,
                  number: '100%',
                  label: 'cuidado',
                ),
              ),
            ],
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mis perros',
                  style: TextStyle(
                    fontFamily: 'Bricolage Grotesque',
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              PressScale(
                onTap: _addDog,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: TinColors.coral,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add_rounded, size: 17, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'Agregar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Expanded(
            child: FutureBuilder<List<Dog>>(
              future: _dogs,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SkeletonCard(height: 100, radius: 20);
                }
                final dogs = snapshot.data ?? [];
                if (dogs.isEmpty) {
                  return Center(
                    child: PressScale(
                      onTap: _addDog,
                      child: GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.add_a_photo_outlined,
                              size: 31,
                              color: TinColors.coral,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Registra a tu primer perro',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Agrega sus vacunas y pedigrí para encontrar conexiones verificadas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.4,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: dogs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) => StaggeredIn(
                    index: index,
                    child: _DogSummary(
                      dog: dogs[index],
                      onEdit: () => _editDog(dogs[index]),
                      onDelete: () => _deleteDog(dogs[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DogSummary extends StatelessWidget {
  const _DogSummary({
    required this.dog,
    required this.onEdit,
    required this.onDelete,
  });
  final Dog dog;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => GlassCard(
    radius: 20,
    padding: const EdgeInsets.all(10),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: 59, height: 63, child: DogPortrait(dog: dog)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${dog.name}, ${dog.age}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                dog.breed,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 5),
              const Row(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: TinColors.green,
                    size: 13,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Perfil completo',
                    style: TextStyle(
                      color: TinColors.green,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<_DogAction>(
          tooltip: 'Administrar perfil',
          onSelected: (action) {
            if (action == _DogAction.edit) onEdit();
            if (action == _DogAction.delete) onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _DogAction.edit,
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Editar perfil'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _DogAction.delete,
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Eliminar perro'),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

enum _DogAction { edit, delete }

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    this.number,
    this.count,
    required this.label,
  });
  final IconData icon;
  final String? number;
  final Future<int>? count;
  final String label;
  @override
  Widget build(BuildContext context) => GlassCard(
    radius: 17,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
    child: Column(
      children: [
        Icon(icon, color: TinColors.coral, size: 17),
        const SizedBox(height: 4),
        if (count == null)
          Text(
            number ?? '0',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          )
        else
          FutureBuilder<int>(
            future: count,
            builder: (context, snapshot) => Text(
              '${snapshot.data ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor),
        ),
      ],
    ),
  );
}
