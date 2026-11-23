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
  String _intention = 'playdate';
  DateTime? _birthDate;
  bool _hasPedigree = false;
  final Map<String, DateTime?> _vaccines = {
    'Rabia': null,
    'Parvovirus / Moquillo': null,
  };
  final Map<String, DateTime?> _vaccineAppliedOn = {
    'Rabia': null,
    'Parvovirus / Moquillo': null,
  };
  final Map<String, String?> _vaccineLabelPhotos = {
    'Rabia': null,
    'Parvovirus / Moquillo': null,
  };
  String? _photo;
  String? _error;
  bool _saving = false;

  int get _stepCount => 3;

  @override
  void initState() {
    super.initState();
    final dog = widget.dog;
    if (dog == null) return;
    _name.text = dog.name;
    _breed.text = dog.breed;
    _sex = dog.sex;
    _intention = dog.intention;
    final today = DateTime.now();
    final estimatedMonths = dog.age < 2 ? 18 : dog.age * 12;
    _birthDate =
        dog.birthDate ??
        DateTime(today.year, today.month - estimatedMonths, today.day);
    _hasPedigree = dog.hasPedigree;
    _pedigreeNumber.text = dog.pedigreeNumber;
    for (final name in _vaccines.keys) {
      final legacyName = name == 'Parvovirus / Moquillo' ? 'Parvovirus' : name;
      _vaccines[name] = DateTime.tryParse(
        dog.vaccines[name] ?? dog.vaccines[legacyName] ?? '',
      );
      _vaccineAppliedOn[name] = DateTime.tryParse(
        dog.vaccineAppliedOn[name] ?? '',
      );
      _vaccineLabelPhotos[name] = dog.vaccineLabelPhotos[name];
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

  bool get _healthRecordsComplete {
    final validExpirations = _vaccines.values.every(
      (date) => date != null && date.isAfter(DateTime.now()),
    );
    if (_intention == 'breeding') {
      if (!validExpirations) return false;
      if (!widget.repository.canStoreHealthLabels) return true;
      return _vaccines.keys.every(
        (name) =>
            _vaccineAppliedOn[name] != null &&
            _vaccineLabelPhotos[name] != null,
      );
    }
    if (!widget.repository.canStoreHealthLabels) return true;
    return _vaccines.keys.every((name) {
      final hasAnyData =
          _vaccineAppliedOn[name] != null ||
          _vaccines[name] != null ||
          _vaccineLabelPhotos[name] != null;
      return !hasAnyData ||
          (_vaccineAppliedOn[name] != null &&
              _vaccineLabelPhotos[name] != null);
    });
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

  Future<void> _chooseVaccineAppliedDate(String name) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _vaccineAppliedOn[name] ?? today,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Fecha de aplicacion: $name',
    );
    if (picked != null) {
      setState(() {
        _vaccineAppliedOn[name] = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickHealthLabel(String name) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1400,
      );
      if (picked != null) {
        setState(() {
          _vaccineLabelPhotos[name] = picked.path;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos abrir tus fotos.')),
        );
      }
    }
  }

  Future<void> _pickPhoto() async {
    if (!widget.repository.canStorePickedPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falta configurar el bucket de fotos de Supabase.'),
        ),
      );
      return;
    }
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
      if (widget.repository.canEditHealthRecords && !_healthRecordsComplete) {
        setState(
          () => _error = _intention == 'breeding'
              ? widget.repository.canStoreHealthLabels
                    ? 'Para cruza captura fecha, vigencia y foto de etiqueta de las dos vacunas.'
                    : 'Las vacunas deben estar vigentes para registrar una cruza.'
              : 'Completa fecha de aplicacion y foto de etiqueta en cada vacuna que agregues.',
        );
        return;
      }
    } else {
      if (_photo == null &&
          widget.dog == null &&
          widget.repository.canStorePickedPhotos) {
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
      intention: _intention,
      birthDate: _birthDate,
      sex: _sex!,
      location: existing?.location ?? 'Ciudad de México',
      distanceKm:
          existing?.distanceKm ??
          (widget.repository.canEditHealthRecords ? 1 : null),
      compatibility:
          existing?.compatibility ??
          (widget.repository.canEditHealthRecords ? 100 : null),
      pedigree: widget.repository.canEditHealthRecords
          ? _hasPedigree
          : existing?.pedigree ?? false,
      hasPedigree: _hasPedigree,
      pedigreeNumber: _hasPedigree ? _pedigreeNumber.text.trim() : '',
      vaccines: {
        for (final entry in _vaccines.entries)
          if (entry.value != null)
            entry.key: entry.value!.toIso8601String().substring(0, 10),
      },
      vaccineAppliedOn: {
        for (final entry in _vaccineAppliedOn.entries)
          if (entry.value != null)
            entry.key: entry.value!.toIso8601String().substring(0, 10),
      },
      vaccineLabelPhotos: {
        for (final entry in _vaccineLabelPhotos.entries)
          if (entry.value != null)
            entry.key:
                entry.value!.startsWith('picked:') ||
                    entry.value!.startsWith('http')
                ? entry.value!
                : 'picked:${entry.value}',
      },
      photo: _photo != null ? 'picked:$_photo' : existing?.photo ?? '',
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
    } catch (error) {
      if (error is StateError && mounted) {
        setState(() {
          _saving = false;
          _error = error.message.toString();
        });
        return;
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'No se pudo guardar el perfil. Revisa tu conexión e intenta de nuevo.';
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
                        'Paso ${_step + 1} de $_stepCount',
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
                value: (_step + 1) / _stepCount,
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
                  ? widget.repository.canEditHealthRecords
                        ? _healthStep()
                        : _pedigreeStep()
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
      const Text(
        'Tipo de conexiÃ³n',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            child: _SelectCard(
              title: 'Convivencia',
              icon: Icons.pets_rounded,
              selected: _intention == 'playdate',
              onTap: () => setState(() => _intention = 'playdate'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SelectCard(
              title: 'Cruza',
              icon: Icons.favorite_rounded,
              selected: _intention == 'breeding',
              onTap: () => setState(() => _intention = 'breeding'),
            ),
          ),
        ],
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

  Widget _pedigreeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Registro de pedigree',
        style: TextStyle(
          fontFamily: 'Bricolage Grotesque',
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      const SizedBox(height: 16),
      GlassCard(
        radius: 19,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _hasPedigree,
          activeThumbColor: TinColors.green,
          title: const Text(
            'Tiene pedigree',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          subtitle: const Text(
            'El numero se enviara para verificacion.',
            style: TextStyle(fontSize: 10),
          ),
          onChanged: (value) => setState(() => _hasPedigree = value),
        ),
      ),
      if (_hasPedigree) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _pedigreeNumber,
          decoration: const InputDecoration(
            labelText: 'Numero de registro',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
      ],
      const SizedBox(height: 18),
      Text(
        'La cartilla de salud se muestra desde la base de datos. En este momento no se puede editar desde la app.',
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
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
        'Cartilla de salud',
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
      ),
      const SizedBox(height: 5),
      Text(
        _intention == 'breeding'
            ? 'Para cruza, captura fechas y una foto legible de cada etiqueta.'
            : 'Las vacunas son opcionales para convivencia.',
        style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
      ),
      const SizedBox(height: 11),
      ..._vaccines.keys.map((name) => _healthRecordEditor(name)),
    ],
  );

  Widget _healthRecordEditor(String name) {
    final labelPhoto = _vaccineLabelPhotos[name];
    final labelImage = labelPhoto == null
        ? null
        : labelPhoto.startsWith('http')
        ? Image.network(labelPhoto, fit: BoxFit.cover)
        : File(labelPhoto).existsSync()
        ? Image.file(File(labelPhoto), fit: BoxFit.cover)
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: GlassCard(
        radius: 18,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            _DateButton(
              label: 'Fecha de aplicacion',
              value: _vaccineAppliedOn[name] == null
                  ? 'Seleccionar fecha'
                  : _formatDate(_vaccineAppliedOn[name]!),
              icon: Icons.event_available_rounded,
              valid: _vaccineAppliedOn[name] != null,
              onTap: () => _chooseVaccineAppliedDate(name),
            ),
            const SizedBox(height: 7),
            _DateButton(
              label: 'Vigente hasta',
              value: _vaccines[name] == null
                  ? 'Seleccionar vencimiento'
                  : _formatDate(_vaccines[name]!),
              icon: Icons.vaccines_outlined,
              valid: _vaccines[name]?.isAfter(DateTime.now()) ?? false,
              onTap: () => _chooseVaccineDate(name),
            ),
            if (widget.repository.canStoreHealthLabels) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _pickHealthLabel(name),
                icon: const Icon(Icons.photo_camera_back_outlined),
                label: Text(
                  labelPhoto == null
                      ? 'Foto de la etiqueta'
                      : 'Cambiar foto de la etiqueta',
                ),
              ),
              if (labelImage != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(height: 100, width: 150, child: labelImage),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

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
        widget.repository.canStorePickedPhotos
            ? 'Agrega al menos una foto clara y reciente.'
            : 'Este proyecto aun no tiene almacenamiento de fotos. Puedes guardar el perfil sin foto.',
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
                    Text(
                      widget.repository.canStorePickedPhotos
                          ? 'Toca para elegir una foto'
                          : 'Foto no disponible por ahora',
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
        child: Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: TinColors.green,
              size: 18,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.repository.canStorePickedPhotos
                    ? 'La foto se guarda en el almacenamiento seguro de TinDog.'
                    : 'El perfil se guardara en la base; se podra agregar una foto cuando se configure Storage.',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
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
