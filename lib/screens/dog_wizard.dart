import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

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
  final _location = TextEditingController();
  final _picker = ImagePicker();
  late Future<List<String>> _breedOptions;
  String? _selectedBreed;
  double? _latitude;
  double? _longitude;
  double? _locationAccuracy;
  bool _loadingLocation = false;
  int _step = 0;
  String? _sex;
  String _intention = 'playdate';
  DateTime? _birthDate;
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
  final Map<String, TextEditingController> _vaccineProducts = {
    'Rabia': TextEditingController(),
    'Parvovirus / Moquillo': TextEditingController(),
  };
  final Map<String, TextEditingController> _vaccineLots = {
    'Rabia': TextEditingController(),
    'Parvovirus / Moquillo': TextEditingController(),
  };
  String? _photo;
  String? _error;
  bool _saving = false;

  int get _stepCount => 3;

  @override
  void initState() {
    super.initState();
    _breedOptions = widget.repository.availableBreeds();
    final dog = widget.dog;
    if (dog == null) {
      _loadCurrentLocation();
      return;
    }
    _name.text = dog.name;
    _selectedBreed = dog.breed.split(' / ').first.trim();
    _location.text = dog.location;
    _latitude = dog.latitude;
    _longitude = dog.longitude;
    _sex = dog.sex;
    _intention = dog.intention;
    final today = DateTime.now();
    final estimatedMonths = dog.age < 2 ? 18 : dog.age * 12;
    _birthDate =
        dog.birthDate ??
        DateTime(today.year, today.month - estimatedMonths, today.day);
    for (final name in _vaccines.keys) {
      final legacyName = name == 'Parvovirus / Moquillo' ? 'Parvovirus' : name;
      _vaccines[name] = DateTime.tryParse(
        dog.vaccines[name] ?? dog.vaccines[legacyName] ?? '',
      );
      _vaccineAppliedOn[name] = DateTime.tryParse(
        dog.vaccineAppliedOn[name] ?? dog.vaccineAppliedOn[legacyName] ?? '',
      );
      _vaccineLabelPhotos[name] =
          dog.vaccineLabelPhotos[name] ?? dog.vaccineLabelPhotos[legacyName];
      _vaccineProducts[name]?.text =
          dog.vaccineProducts[name] ?? dog.vaccineProducts[legacyName] ?? '';
      _vaccineLots[name]?.text =
          dog.vaccineLots[name] ?? dog.vaccineLots[legacyName] ?? '';
    }
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    for (final controller in _vaccineProducts.values) {
      controller.dispose();
    }
    for (final controller in _vaccineLots.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final location = await widget.repository.currentLocation();
      if (!mounted) return;
      setState(() {
        if (_location.text.trim().isEmpty && location.city != null) {
          _location.text = location.city!.trim();
        }
        _latitude ??= location.latitude;
        _longitude ??= location.longitude;
      });
    } catch (_) {
      // The user can enter the city manually if it has not been saved yet.
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _loadingLocation = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationMessage(
          'Activa la ubicación del celular e inténtalo de nuevo.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationMessage(
          'El permiso de ubicación está bloqueado. Actívalo en Ajustes de la app.',
          openSettings: true,
        );
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationMessage(
          'Permite la ubicación para capturar las coordenadas.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationAccuracy = position.accuracy;
      });
    } on _LocationMessage catch (message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.message),
            action: message.openSettings
                ? SnackBarAction(
                    label: 'Ajustes',
                    onPressed: Geolocator.openAppSettings,
                  )
                : null,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos obtener el GPS. Revisa el permiso y vuelve a intentarlo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
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
          _vaccineLabelPhotos[name] != null ||
          _vaccineProducts[name]!.text.trim().isNotEmpty ||
          _vaccineLots[name]!.text.trim().isNotEmpty;
      return !hasAnyData || _vaccineAppliedOn[name] != null;
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
      helpText: 'Fecha de aplicaci\u00f3n: $name',
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
          (_selectedBreed ?? '').trim().isEmpty ||
          (_location.text.trim().isEmpty &&
              (_latitude == null || _longitude == null)) ||
          _sex == null ||
          _birthDate == null) {
        setState(
          () => _error = 'Completa nombre, raza, sexo y fecha de nacimiento; escribe una ciudad o usa el botón para capturar el GPS.',
        );
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
      if (widget.repository.canEditHealthRecords && !_healthRecordsComplete) {
        setState(
          () => _error = _intention == 'breeding'
              ? widget.repository.canStoreHealthLabels
                    ? 'Para cruza captura fecha, vigencia y foto de etiqueta de las dos vacunas.'
                    : 'Las vacunas deben estar vigentes para registrar una cruza.'
              : 'Para guardar una vacuna, selecciona su fecha de aplicación. La foto de la etiqueta es opcional para convivencia.',
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
      breed: _selectedBreed!.trim(),
      age: ((_monthsOld ?? 18) / 12).floor(),
      intention: _intention,
      birthDate: _birthDate,
      sex: _sex!,
      location: _location.text.trim(),
      latitude: _latitude,
      longitude: _longitude,
      distanceKm:
          existing?.distanceKm ??
          (widget.repository.canEditHealthRecords ? 1 : null),
      compatibility:
          existing?.compatibility ??
          (widget.repository.canEditHealthRecords ? 100 : null),
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
      vaccineProducts: {
        for (final entry in _vaccineProducts.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
      },
      vaccineLots: {
        for (final entry in _vaccineLots.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
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
          _error = 'No se pudo guardar el perfil: $error';
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
      _breedSelector(),
      const SizedBox(height: 12),
      TextField(
        controller: _location,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Ubicación (ciudad)',
          hintText: 'Ej. Guadalajara, Jalisco',
          helperText: 'Se guarda como ciudad de tu cuenta. El botón recupera la ciudad guardada.',
          prefixIcon: const Icon(Icons.location_on_outlined),
          suffixIcon: IconButton(
            tooltip: 'Recuperar ciudad guardada en tu cuenta',
            onPressed: _loadCurrentLocation,
            icon: const Icon(Icons.restore_rounded),
          ),
        ),
      ),
      const SizedBox(height: 9),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _loadingLocation ? null : _useCurrentLocation,
          icon: _loadingLocation
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location_rounded),
          label: Text(
            _loadingLocation
                ? 'Obteniendo ubicación del celular…'
                : 'Usar ubicación actual del celular',
          ),
        ),
      ),
      if (_latitude != null && _longitude != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'GPS listo: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}${_locationAccuracy == null ? '' : ' · precisión ~${_locationAccuracy!.round()} m'}. Se guarda privado; otros perfiles solo reciben la distancia aproximada.',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 11,
              height: 1.35,
            ),
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
        'Tipo de conexión',
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

  Widget _breedSelector() => FutureBuilder<List<String>>(
    future: _breedOptions,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done &&
          !snapshot.hasData) {
        return const InputDecorator(
          decoration: InputDecoration(
            labelText: 'Raza',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          child: Text('Cargando razas de la base de datos…'),
        );
      }
      if (snapshot.hasError) {
        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Raza',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          child: Row(
            children: [
              const Expanded(child: Text('No se pudo cargar el catálogo.')),
              TextButton(
                onPressed: () => setState(
                  () => _breedOptions = widget.repository.availableBreeds(),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        );
      }

      final breeds = List<String>.from(snapshot.data ?? const []);
      final selectedBreed = breeds.contains(_selectedBreed)
          ? _selectedBreed
          : null;
      return DropdownButtonFormField<String>(
        key: ValueKey(breeds.join('|')),
        initialValue: selectedBreed,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Raza',
          prefixIcon: Icon(Icons.search_rounded),
        ),
        hint: const Text('Selecciona una raza'),
        items: breeds
            .map(
              (breed) => DropdownMenuItem<String>(
                value: breed,
                child: Text(breed, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        validator: (value) => (value ?? '').trim().isEmpty
            ? 'Selecciona una raza del catálogo.'
            : null,
        onChanged: (breed) {
          setState(() => _selectedBreed = breed);
        },
      );
    },
  );

  Widget _healthStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Salud y vacunas',
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
            TextField(
              controller: _vaccineProducts[name],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre del producto o vacuna',
                prefixIcon: Icon(Icons.medication_outlined),
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: _vaccineLots[name],
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Número de lote',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 7),
            _DateButton(
              label: 'Fecha de aplicaci\u00f3n',
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

class _LocationMessage implements Exception {
  const _LocationMessage(this.message, {this.openSettings = false});

  final String message;
  final bool openSettings;
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
