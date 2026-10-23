import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/repository.dart';
import '../models/dog.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DogWizard extends StatefulWidget {
  const DogWizard({super.key, required this.repository, this.dog});
  final TinDogRepository repository;
  final Dog? dog;
  @override
  State<DogWizard> createState() => _DogWizardState();
}

class _DogWizardState extends State<DogWizard> {
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _pedigreeNumber = TextEditingController();
  final _picker = ImagePicker();
  int _step = 0;
  String? _sex;
  DateTime? _birthDate;
  bool _hasPedigree = false;
  final Map<String, DateTime?> _vaccines = {
    'Rabia': null,
    'Parvovirus': null,
    'Moquillo': null,
  };
  String? _photo;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final dog = widget.dog;
    if (dog == null) return;
    _name.text = dog.name;
    _breed.text = dog.breed;
    _sex = dog.sex;
    final today = DateTime.now();
    final estimatedMonths = dog.age < 2 ? 18 : dog.age * 12;
    _birthDate =
        dog.birthDate ??
        DateTime(today.year, today.month - estimatedMonths, today.day);
    _hasPedigree = dog.pedigree;
    _pedigreeNumber.text = dog.pedigreeNumber;
    for (final name in _vaccines.keys) {
      _vaccines[name] = DateTime.tryParse(dog.vaccines[name] ?? '');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _pedigreeNumber.dispose();
    super.dispose();
  }

  int? get _monthsOld {
    if (_birthDate == null) return null;
    final now = DateTime.now();
    var months =
        (now.year - _birthDate!.year) * 12 + now.month - _birthDate!.month;
    if (now.day < _birthDate!.day) months--;
    return months;
  }

  Future<void> _chooseBirthDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? DateTime(today.year - 2, today.month, today.day),
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Fecha de nacimiento',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _chooseVaccineDate(String name) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _vaccines[name] ?? DateTime(today.year + 1, today.month, today.day),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: DateTime(today.year + 10),
      helpText: 'Vigencia de $name',
    );
    if (picked != null) {
      setState(() {
        _vaccines[name] = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked != null) {
        setState(() {
          _photo = picked.path;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos abrir tus fotos. Revisa los permisos de la app.',
            ),
          ),
        );
      }
    }
  }

  void _next() {
    setState(() => _error = null);
    if (_step == 0) {
      if (_name.text.trim().isEmpty ||
          _breed.text.trim().isEmpty ||
          _sex == null ||
          _birthDate == null) {
        setState(() => _error = 'Completa los campos obligatorios.');
        return;
      }
      if ((_monthsOld ?? 0) < 18) {
        setState(
          () => _error =
              'Tu perro necesita tener al menos 18 meses para registrarlo.',
        );
        return;
      }
    } else if (_step == 1) {
      if (_hasPedigree && _pedigreeNumber.text.trim().isEmpty) {
        setState(() => _error = 'Agrega el número de pedigrí.');
        return;
      }
      if (_vaccines.values.any(
        (date) => date == null || !date.isAfter(DateTime.now()),
      )) {
        setState(
          () => _error = 'Las vacunas de rabia, parvovirus y moquillo deben estar vigentes.',
        );
        return;
      }
    } else {
      if (_photo == null && widget.dog == null) {
        setState(() => _error = 'Agrega al menos una foto de tu perro.');
        return;
      }
      _save();
      return;
    }
    setState(() => _step++);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final existing = widget.dog;
    final dog = Dog(
      id: existing?.id ?? 'mine_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      breed: _breed.text.trim(),
      age: ((_monthsOld ?? 18) / 12).floor(),
      birthDate: _birthDate,
      sex: _sex!,
      location: existing?.location ?? 'Ciudad de México',
      distanceKm: existing?.distanceKm ?? 1,
      compatibility: existing?.compatibility ?? 100,
      pedigree: _hasPedigree,
      pedigreeNumber: _hasPedigree ? _pedigreeNumber.text.trim() : '',
      vaccines: _vaccines.map(
        (key, value) =>
            MapEntry(key, value!.toIso8601String().substring(0, 10)),
      ),
      photo: _photo != null ? 'picked:$_photo' : existing!.photo,
      about: existing?.about ?? 'Perfil registrado por su familia en TinDog.',
      color: existing?.color ?? '#FFDCCB',
    );
    try {
      if (existing == null) {
        await widget.repository.addDog(dog);
      } else {
        await widget.repository.updateDog(dog);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'No se pudo guardar la foto. Intenta con otra imagen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 18, 9),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (_step == 0) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _step--;
                        _error = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.dog == null
                            ? 'Registrar mi perro'
                            : 'Editar perfil',
                        style: TextStyle(
                          fontFamily: 'Bricolage Grotesque',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      Text(
                        'Paso ${_step + 1} de 3',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.pets_rounded, color: TinColors.coral),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: (_step + 1) / 3,
                color: TinColors.coral,
                backgroundColor: TinColors.peach,
                minHeight: 6,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(21, 21, 21, 14),
              child: _step == 0
                  ? _identityStep()
                  : _step == 1
                  ? _healthStep()
                  : _photoStep(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: TinColors.coral,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: PrimaryButton(
              label: _step == 2
                  ? widget.dog == null
                        ? 'Guardar perfil'
                        : 'Guardar cambios'
                  : 'Continuar',
              icon: _step == 2
                  ? Icons.check_rounded
                  : Icons.arrow_forward_rounded,
              loading: _saving,
              onPressed: _saving ? null : _next,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _identityStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Cuéntanos de tu perro',
        style: TextStyle(
          fontFamily: 'Bricolage Grotesque',
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Esta información ayuda a encontrarle una pareja compatible.',
        style: TextStyle(
          color: Theme.of(context).hintColor,
          fontSize: 12,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          prefixIcon: Icon(Icons.pets_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _breed,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Raza',
          hintText: 'Ej. Golden Retriever',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 17),
      const Text(
        'Sexo',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            child: _SelectCard(
              title: 'Hembra',
              icon: Icons.female_rounded,
              selected: _sex == 'Hembra',
              onTap: () => setState(() => _sex = 'Hembra'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SelectCard(
              title: 'Macho',
              icon: Icons.male_rounded,
              selected: _sex == 'Macho',
              onTap: () => setState(() => _sex = 'Macho'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _DateButton(
        label: 'Fecha de nacimiento',
        value: _birthDate == null
            ? 'Seleccionar fecha'
            : _formatDate(_birthDate!),
        icon: Icons.cake_outlined,
        onTap: _chooseBirthDate,
      ),
      if (_monthsOld != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Edad: ${_monthsOld! ~/ 12} años y ${_monthsOld! % 12} meses',
            style: TextStyle(
              fontSize: 11,
              color: (_monthsOld ?? 0) >= 18
                  ? TinColors.green
                  : TinColors.coral,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      const SizedBox(height: 11),
      GlassCard(
        radius: 17,
        padding: const EdgeInsets.all(13),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: TinColors.coral, size: 18),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'La edad mínima para cruza es de 18 meses.',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _healthStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Salud y pedigrí',
        style: TextStyle(
          fontFamily: 'Bricolage Grotesque',
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Compartir información vigente cuida a toda la manada.',
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
      ),
      const SizedBox(height: 17),
      GlassCard(
        radius: 19,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _hasPedigree,
          activeThumbColor: TinColors.green,
          title: const Text(
            'Tiene pedigrí',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          subtitle: const Text(
            'Registro genealógico oficial',
            style: TextStyle(fontSize: 10),
          ),
          onChanged: (value) => setState(() => _hasPedigree = value),
        ),
      ),
      if (_hasPedigree) ...[
        const SizedBox(height: 11),
        TextField(
          controller: _pedigreeNumber,
          decoration: const InputDecoration(
            labelText: 'Número de pedigrí',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
      ],
      const SizedBox(height: 19),
      const Text(
        'Vigencia de vacunas',
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
      ),
      const SizedBox(height: 5),
      Text(
        'Las tres fechas de vencimiento deben ser futuras.',
        style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
      ),
      const SizedBox(height: 11),
      ..._vaccines.keys.map(
        (name) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: _DateButton(
            label: name,
            value: _vaccines[name] == null
                ? 'Elegir vencimiento'
                : _formatDate(_vaccines[name]!),
            icon: Icons.vaccines_outlined,
            valid: _vaccines[name]?.isAfter(DateTime.now()) ?? false,
            onTap: () => _chooseVaccineDate(name),
          ),
        ),
      ),
    ],
  );

  Widget _photoStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Una buena foto hace match',
        style: TextStyle(
          fontFamily: 'Bricolage Grotesque',
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Agrega al menos una foto clara y reciente.',
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
      ),
      const SizedBox(height: 20),
      PressScale(
        onTap: _pickPhoto,
        child: Container(
          width: double.infinity,
          height: 290,
          decoration: BoxDecoration(
            color: TinColors.peach.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(27),
            border: Border.all(
              color: TinColors.coral.withValues(alpha: .35),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: _photo == null && widget.dog == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_a_photo_rounded,
                        color: TinColors.coral,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Toca para elegir una foto',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'JPG o PNG desde tu galería',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    _photo == null
                        ? DogPortrait(dog: widget.dog!)
                        : Image.file(File(_photo!), fit: BoxFit.cover),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: TinColors.coral,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 13),
      GlassCard(
        radius: 18,
        padding: const EdgeInsets.all(13),
        child: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: TinColors.green, size: 18),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Tu información se guarda localmente en este dispositivo.',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.valid = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool valid;
  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? TinColors.darkCard
            : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .14),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: valid ? TinColors.green : TinColors.coral,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.calendar_month_rounded,
            size: 17,
            color: TinColors.coral,
          ),
        ],
      ),
    ),
  );
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 54,
      decoration: BoxDecoration(
        color: selected
            ? TinColors.peach.withValues(alpha: .65)
            : (Theme.of(context).brightness == Brightness.dark
                  ? TinColors.darkCard
                  : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? TinColors.coral : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: selected ? TinColors.coral : Theme.of(context).hintColor,
            size: 19,
          ),
          const SizedBox(width: 7),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? TinColors.coral : null,
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
