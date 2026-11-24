import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dog.dart';
import 'repository.dart';

String _registrationPasswordError(AuthException error) {
  if (error is AuthWeakPasswordException && error.reasons.isNotEmpty) {
    final requirements = error.reasons
        .map(_passwordReasonInSpanish)
        .toSet()
        .join(' y ');
    return 'Supabase pide que la contraseña $requirements.';
  }

  final message = error.message.trim();
  if (message.isNotEmpty && message.toLowerCase() != 'weak password') {
    return 'Supabase rechazó la contraseña: $message';
  }
  return 'Supabase rechazó la contraseña. Revisa los requisitos de contraseña de Authentication en el proyecto.';
}

String _passwordReasonInSpanish(String reason) {
  final normalized = reason.toLowerCase();
  if (normalized == 'too_short' ||
      normalized == 'length' ||
      normalized.contains('at least') ||
      normalized.contains('shorter')) {
    final minLength = RegExp(r'\d+').firstMatch(reason)?.group(0);
    return minLength == null
        ? 'tenga más caracteres'
        : 'tenga al menos $minLength caracteres';
  }
  if (normalized.contains('uppercase')) return 'incluya una mayúscula';
  if (normalized.contains('lowercase')) return 'incluya una minúscula';
  if (normalized.contains('number') || normalized.contains('digit')) {
    return 'incluya un número';
  }
  if (normalized.contains('symbol') || normalized.contains('special')) {
    return 'incluya un símbolo';
  }
  if (normalized == 'characters') {
    return 'cumpla los tipos de caracteres requeridos (por ejemplo, símbolos)';
  }
  if (normalized.contains('leaked') ||
      normalized.contains('compromised') ||
      normalized.contains('pwned')) {
    return 'no aparezca en una lista de contraseñas filtradas; prueba otra';
  }
  return reason;
}

class SupabaseTinDogRepository implements TinDogRepository {
  SupabaseTinDogRepository(this._client);

  final SupabaseClient _client;
  final Map<String, RealtimeChannel> _chatChannelsByDog = {};
  final Map<String, bool> _pendingTypingByDog = {};
  final Map<String, Map<String, dynamic>> _conversationsByDog = {};
  static const _photoBucket = 'dog-photos';
  static const _healthLabelBucket = 'health-labels';

  @override
  String? get displayName =>
      _client.auth.currentUser?.userMetadata?['display_name'] as String?;

  @override
  bool get canReplayDiscovery => false;

  @override
  bool get canClearConversation => false;

  @override
  bool get canStorePickedPhotos => true;

  @override
  bool get canEditHealthRecords => true;

  @override
  bool get canStoreHealthLabels => true;

  @override
  bool get supportsDistanceFilter => true;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Inicia sesión para continuar.');
    return id;
  }

  @override
  Future<String?> restoreSession() async => _client.auth.currentUser?.email;

  @override
  Future<bool> login(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return response.user != null;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      final code = error.code?.toLowerCase() ?? '';
      if (code == 'email_not_confirmed' ||
          message.contains('email not confirmed')) {
        throw StateError(
          'La cuenta existe, pero falta confirmar el correo. Abre el mensaje de confirmación y pulsa su enlace antes de iniciar sesión.',
        );
      }
      if (code == 'invalid_credentials' ||
          message.contains('invalid login credentials')) {
        throw StateError(
          'Supabase no reconoce ese correo y contraseña. Verifica que sean los mismos que usaste al crear la cuenta.',
        );
      }
      if (error.statusCode == '429' ||
          code == 'over_request_rate_limit' ||
          message.contains('rate limit') ||
          message.contains('too many requests')) {
        throw StateError(
          'Hubo demasiados intentos de inicio de sesión. Espera unos minutos y vuelve a probar.',
        );
      }
      if (error.statusCode == null) {
        throw StateError(
          'No pudimos conectar con Supabase. Revisa la conexión a internet y vuelve a intentar.',
        );
      }
      throw StateError(
        'Supabase rechazó el inicio de sesión (código: ${error.code ?? error.statusCode}).',
      );
    }
  }

  @override
  Future<RegistrationResult> register(
    String name,
    String email,
    String password,
  ) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {'display_name': name.trim()},
      );
      final user = response.user;
      if (user == null) {
        throw StateError(
          'Supabase no devolvió la cuenta. Vuelve a intentar y comparte el mensaje si falla.',
        );
      }
      final identities = user.identities;
      if (response.session == null &&
          identities != null &&
          identities.isEmpty) {
        return RegistrationResult.alreadyRegistered;
      }
      if (response.session == null) {
        return RegistrationResult.confirmationRequired;
      }
      return RegistrationResult.signedIn;
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      final code = error.code?.toLowerCase() ?? '';
      if (code == 'email_exists' ||
          code == 'user_already_exists' ||
          message.contains('already registered') ||
          message.contains('already been registered') ||
          message.contains('user exists')) {
        return RegistrationResult.alreadyRegistered;
      }
      if (error.statusCode == '429' ||
          code == 'over_email_send_rate_limit' ||
          code == 'over_request_rate_limit' ||
          message.contains('rate limit') ||
          message.contains('too many requests')) {
        throw StateError(
          'Supabase limitó temporalmente los registros por correo. Espera unos minutos antes de volver a intentar.',
        );
      }
      if (code == 'signup_disabled' ||
          message.contains('signup is disabled') ||
          message.contains('signups not allowed')) {
        throw StateError(
          'El registro de cuentas está desactivado en Supabase. Activa Allow new users to sign up en Authentication.',
        );
      }
      if (code == 'weak_password' || error is AuthWeakPasswordException) {
        throw StateError(_registrationPasswordError(error));
      }
      if (message.contains('database error saving new user')) {
        throw StateError(
          'Auth recibió el registro, pero falló al guardar el perfil. Pídele a tu compañero revisar el trigger de auth.users que crea la fila en public.users.',
        );
      }
      if (error.statusCode == null) {
        throw StateError(
          'No pudimos conectar con Supabase. Revisa internet e intenta de nuevo.',
        );
      }
      throw StateError(
        'Supabase rechazó el registro (código: ${error.code ?? error.statusCode}).',
      );
    }
  }

  @override
  Future<AccountLocation> currentLocation() async {
    String? city;
    double? latitude;
    double? longitude;
    try {
      final rows = await _client
          .from('users')
          .select('city')
          .eq('id', _userId)
          .limit(1);
      city = rows.isEmpty ? null : rows.first['city']?.toString();
    } on PostgrestException {
      // City is optional if this Supabase schema does not include that field.
    }
    try {
      final rows = await _client
          .from('user_locations')
          .select('latitude,longitude')
          .eq('user_id', _userId)
          .limit(1);
      if (rows.isNotEmpty) {
        latitude = (rows.first['latitude'] as num?)?.toDouble();
        longitude = (rows.first['longitude'] as num?)?.toDouble();
      }
    } on PostgrestException {
      // GPS is enabled after the one-time location migration is applied.
    }
    return AccountLocation(
      city: city,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<bool> refreshDeviceLocation() async {
    final location = await captureDeviceCoordinates();
    if (location == null || !location.hasCoordinates) {
      debugPrint(
        'TinDog GPS: no se obtuvieron coordenadas del dispositivo; revisa '
        'servicios de ubicación y permisos.',
      );
      return false;
    }
    await _saveCurrentLocation(
      '',
      latitude: location.latitude,
      longitude: location.longitude,
    );
    return true;
  }

  Future<void> _saveCurrentLocation(
    String city, {
    double? latitude,
    double? longitude,
  }) async {
    final userUpdates = <String, dynamic>{};
    if (city.trim().isNotEmpty) userUpdates['city'] = city.trim();
    if (latitude != null && longitude != null) {
      // PostGIS geography accepts WKT through PostgREST. WKT points use
      // longitude first (x), then latitude (y), in SRID 4326.
      userUpdates['location'] = 'POINT($longitude $latitude)';
      userUpdates['location_updated_at'] = DateTime.now()
          .toUtc()
          .toIso8601String();
    }
    if (userUpdates.isNotEmpty) {
      try {
        final rows = await _client
            .from('users')
            .update(userUpdates)
            .eq('id', _userId)
            .select('id');
        if (rows.isEmpty) {
          throw StateError(
            'No encontramos tu perfil en public.users para actualizar la ubicación.',
          );
        }
      } on PostgrestException catch (error) {
        debugPrint(
          'TinDog GPS: Supabase rechazó actualizar public.users '
          '(${error.code}): ${error.message}',
        );
        throw StateError(
          'Supabase rechazó actualizar public.users '
          '(${error.code ?? 'sin código'}): ${error.message}. Confirma que '
          'existan users.location/location_updated_at y la política '
          'users_update_own.',
        );
      }
    }
    if (latitude != null && longitude != null) {
      try {
        final rows = await _client
            .from('user_locations')
            .upsert({
              'user_id': _userId,
              'latitude': latitude,
              'longitude': longitude,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'user_id')
            .select('user_id');
        if (rows.isEmpty) {
          throw StateError(
            'Supabase no devolvió la fila guardada. Revisa las políticas '
            'SELECT e INSERT/UPDATE de public.user_locations.',
          );
        }
      } on PostgrestException catch (error) {
        debugPrint(
          'TinDog GPS: Supabase rechazó el upsert en user_locations '
          '(${error.code}): ${error.message}',
        );
        throw StateError(
          'Supabase rechazó el guardado (${error.code ?? 'sin código'}): '
          '${error.message}. Revisa la tabla public.user_locations y sus '
          'permisos RLS.',
        );
      }
    }
  }

  @override
  Future<void> logout() => _client.auth.signOut();

  @override
  Future<List<String>> availableBreeds() async {
    final rows = await _client.from('breeds').select('name').order('name');
    final names = rows
        .map((row) => row['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (!names.any((name) => name.toLowerCase() == 'mestizo')) {
      names.add('Mestizo');
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  @override
  Future<int> discoveryDistanceKm() async {
    final dogIds = await _myDogIds();
    if (dogIds.isEmpty) return 100;
    try {
      final rows = await _client
          .from('dog_preferences')
          .select('dog_id,max_distance_km,only_pedigree')
          .inFilter('dog_id', dogIds);
      final saved = {
        for (final row in rows)
          row['dog_id'].toString(): (row['max_distance_km'] as num?)?.toInt(),
      };
      final stalePedigreeFilterIds = rows
          .where((row) => row['only_pedigree'] == true)
          .map((row) => row['dog_id'].toString())
          .toList();
      if (stalePedigreeFilterIds.isNotEmpty) {
        await _client
            .from('dog_preferences')
            .update({'only_pedigree': false})
            .inFilter('dog_id', stalePedigreeFilterIds);
      }
      final missingIds = dogIds.where((id) => !saved.containsKey(id)).toList();
      if (missingIds.isNotEmpty) {
        await _client
            .from('dog_preferences')
            .upsert(
              [
                for (final id in missingIds)
                  {
                    'dog_id': id,
                    'max_distance_km': 100,
                    'only_pedigree': false,
                  },
              ],
              onConflict: 'dog_id',
              ignoreDuplicates: true,
            );
      }
      final selectedDistance = saved[dogIds.first];
      final distance = saved.containsKey(dogIds.first)
          ? selectedDistance ?? 25
          : 100;
      return distance.clamp(5, 100).toInt();
    } on PostgrestException catch (error) {
      debugPrint(
        'TinDog: no se pudo leer la distancia preferida (${error.code}): ${error.message}',
      );
      throw StateError(
        'No se pudieron actualizar las preferencias de búsqueda (${error.code}): ${error.message}',
      );
    }
  }

  @override
  Future<void> updateDiscoveryDistanceKm(int distanceKm) async {
    final dogIds = await _myDogIds();
    if (dogIds.isEmpty) return;
    final distance = distanceKm.clamp(5, 100).toInt();
    await _client.from('dog_preferences').upsert([
      for (final id in dogIds)
        {'dog_id': id, 'max_distance_km': distance, 'only_pedigree': false},
    ], onConflict: 'dog_id');
  }

  Future<List<String>> _myDogIds() async {
    final rows = await _client
        .from('dogs')
        .select('id')
        .eq('owner_id', _userId)
        .eq('is_deleted', false)
        .order('created_at', ascending: false);
    return rows.map((row) => row['id'].toString()).toList();
  }

  @override
  Future<List<Dog>> discoverDogs({String? sourceDogId}) async {
    final ownDogIds = await _myDogIds();
    if (ownDogIds.isEmpty) {
      throw StateError(
        'Primero registra un perfil de perro para ver candidatos.',
      );
    }
    if (sourceDogId != null && !ownDogIds.contains(sourceDogId)) {
      throw StateError('El perro seleccionado no pertenece a esta cuenta.');
    }

    final candidates = <String, Dog>{};
    final discoveryDogIds = sourceDogId == null
        ? ownDogIds
        : <String>[sourceDogId];
    for (final ownDogId in discoveryDogIds) {
      dynamic result;
      try {
        result = await _client.rpc(
          'get_candidates',
          params: {
            'p_dog_id': ownDogId,
            'p_limit': 20,
            'p_exclude_ids': <String>[],
          },
        );
      } on PostgrestException catch (error) {
        final message = error.message.toLowerCase();
        if (message.contains('location_required')) {
          throw StateError(
            'Actualiza la ubicaci\u00f3n de tu cuenta para buscar candidatos.',
          );
        }
        if (message.contains('dog_not_owned')) {
          throw StateError('El perro elegido no pertenece a esta cuenta.');
        }
        if (message.contains('not_authenticated')) {
          throw StateError('Inicia sesi\u00f3n para buscar candidatos.');
        }
        if (error.code == 'PGRST202') {
          throw StateError(
            'Supabase no encontr\u00f3 la funci\u00f3n get_candidates. Confirma que el script est\u00e9 aplicado en este proyecto.',
          );
        }
        debugPrint(
          'TinDog get_candidates rechaz\u00f3 la consulta (${error.code}): ${error.message}',
        );
        throw StateError(
          'get_candidates fall\u00f3 (${error.code ?? 'sin c\u00f3digo'}): ${error.message}',
        );
      }

      if (result is! List) {
        throw StateError(
          'Supabase devolvi\u00f3 una respuesta inv\u00e1lida de get_candidates.',
        );
      }
      for (final value in result) {
        if (value is! Map) {
          throw StateError(
            'Supabase devolvi\u00f3 un candidato con formato inv\u00e1lido.',
          );
        }
        final row = Map<String, dynamic>.from(value);
        final dog = await _dogFromCandidate(row, sourceDogId: ownDogId);
        candidates.putIfAbsent(dog.id, () => dog);
      }
    }
    final healthByDogId = await _candidateHealthForDogs(
      candidates.keys.toList(),
    );
    return candidates.values.map((dog) {
      final health = healthByDogId[dog.id];
      if (health == null) return dog;
      return dog.withHealthData(
        vaccines: health.vaccines,
        vaccineAppliedOn: health.appliedOn,
        vaccineProducts: health.products,
        vaccineLots: health.lots,
      );
    }).toList();
  }

  Future<Map<String, _CandidateHealthData>> _candidateHealthForDogs(
    List<String> dogIds,
  ) async {
    if (dogIds.isEmpty) return {};
    final dataByDogId = <String, _CandidateHealthData>{};
    _CandidateHealthData dataFor(String dogId) =>
        dataByDogId.putIfAbsent(dogId, _CandidateHealthData.new);

    final statusRows = await _optionalRows(
      () async => await _client
          .from('dog_health_status')
          .select('dog_id,kind,name,expires_on,status')
          .inFilter('dog_id', dogIds),
    );
    for (final row in statusRows) {
      if (row['kind'] != 'vaccine' ||
          row['name'] == null ||
          row['expires_on'] == null) {
        continue;
      }
      final dogId = row['dog_id'].toString();
      final name = row['name'].toString();
      final expiry = row['expires_on'].toString();
      final previous = dataFor(dogId).vaccines[name];
      if (previous == null || expiry.compareTo(previous) > 0) {
        dataFor(dogId).vaccines[name] = expiry;
      }
    }

    final typeRows = await _optionalRows(
      () async => await _client
          .from('health_item_types')
          .select('id,name,kind')
          .eq('kind', 'vaccine'),
    );
    final typeNames = {
      for (final row in typeRows) row['id'].toString(): row['name'].toString(),
    };
    final recordRows = await _optionalRows(
      () async => await _client
          .from('dog_health_records')
          .select(
            'dog_id,type_id,applied_on,expires_on,product_name,lot_number',
          )
          .inFilter('dog_id', dogIds)
          .eq('verification_status', 'approved')
          .order('created_at', ascending: false),
    );
    for (final row in recordRows) {
      final name = typeNames[row['type_id'].toString()];
      if (name == null) continue;
      final data = dataFor(row['dog_id'].toString());
      final appliedOn = row['applied_on']?.toString();
      if (appliedOn != null) data.appliedOn.putIfAbsent(name, () => appliedOn);
      final expiry = row['expires_on']?.toString();
      if (expiry != null) data.vaccines.putIfAbsent(name, () => expiry);
      final product = row['product_name']?.toString().trim();
      if (product != null && product.isNotEmpty) {
        data.products.putIfAbsent(name, () => product);
      }
      final lot = row['lot_number']?.toString().trim();
      if (lot != null && lot.isNotEmpty) data.lots.putIfAbsent(name, () => lot);
    }
    return dataByDogId;
  }

  Future<Dog> _dogFromCandidate(
    Map<String, dynamic> row, {
    required String sourceDogId,
  }) async {
    final id = row['dog_id']?.toString() ?? '';
    if (id.isEmpty) {
      throw StateError('get_candidates devolvió un perro sin dog_id.');
    }

    String breedName(dynamic value) => value is Map
        ? value['name']?.toString().trim() ?? ''
        : value?.toString().trim() ?? '';

    final mixed = row['is_mixed'] == true;
    final breeds = [
      breedName(row['breed']),
      breedName(row['secondary_breed']),
    ].where((name) => name.isNotEmpty).toList();
    final breed = mixed
        ? 'Mestizo'
        : breeds.isEmpty
        ? 'Raza no especificada'
        : breeds.join(' / ');

    final ageValue = row['age_months'];
    final ageMonths = ageValue is num
        ? ageValue.toInt()
        : int.tryParse(ageValue?.toString() ?? '') ?? 0;
    final distanceValue = row['distance_km'];
    final scoreValue = row['score'];
    final photos = row['photos'];
    var photo = '';
    if (photos is List && photos.isNotEmpty && photos.first is Map) {
      final photoPath = (photos.first as Map)['url']?.toString() ?? '';
      photo = await _resolvePhotoUrl(photoPath) ?? '';
    }

    final sex = switch (row['sex']?.toString().toLowerCase()) {
      'female' => 'Hembra',
      'male' => 'Macho',
      'hembra' => 'Hembra',
      'macho' => 'Macho',
      _ => row['sex']?.toString() ?? '',
    };

    return Dog(
      id: id,
      sourceDogId: sourceDogId,
      name: row['name']?.toString() ?? '',
      breed: breed,
      age: ageMonths ~/ 12,
      intention:
          row['mode']?.toString() ??
          row['primary_intention']?.toString() ??
          'playdate',
      sex: sex,
      location: 'GPS',
      distanceKm: distanceValue is num ? distanceValue.toInt() : null,
      compatibility: scoreValue is num ? scoreValue.toInt() : null,
      vaccines: const {},
      photo: photo,
      about: row['bio']?.toString() ?? '',
      color: '#FFDCCB',
    );
  }

  @override
  Future<void> resetDiscovery() async {
    // The database intentionally exposes swipes as read-only. A client must not
    // delete them to replay profiles.
  }

  @override
  Future<Dog?> dogById(String dogId) async {
    final rows = await _client.from('dogs').select().eq('id', dogId).limit(1);
    if (rows.isEmpty) return null;
    final dogs = await _hydrateDogs(List<Map<String, dynamic>>.from(rows));
    return dogs.isEmpty ? null : dogs.first;
  }

  @override
  Future<List<Dog>> myDogs() async {
    final rows = await _client
        .from('dogs')
        .select()
        .eq('owner_id', _userId)
        .eq('is_deleted', false)
        .order('created_at', ascending: false);
    return _hydrateDogs(List<Map<String, dynamic>>.from(rows));
  }

  @override
  Future<void> addDog(Dog dog) async {
    final userId = _userId;
    if (dog.location.trim().isNotEmpty || dog.latitude != null) {
      await _saveCurrentLocation(
        dog.location,
        latitude: dog.latitude,
        longitude: dog.longitude,
      );
    }
    final id = _isUuid(dog.id) ? dog.id : _newUuid();
    final photoUrl = await _photoUrlFor(dog, id, userId);
    await _client.from('dogs').insert({
      'id': id,
      'owner_id': userId,
      ...await _dogToRow(dog),
    });
    if (photoUrl != null) {
      await _client.from('dog_photos').insert({
        'dog_id': id,
        'url': photoUrl,
        'position': 0,
      });
    }
    await _saveHealthRecords(id, dog, userId);
  }

  @override
  Future<void> updateDog(Dog dog) async {
    final userId = _userId;
    if (dog.location.trim().isNotEmpty || dog.latitude != null) {
      await _saveCurrentLocation(
        dog.location,
        latitude: dog.latitude,
        longitude: dog.longitude,
      );
    }
    final photoUrl = dog.photo.startsWith('picked:')
        ? await _photoUrlFor(dog, dog.id, userId)
        : null;
    final values = await _dogToRow(dog);
    final rows = await _client
        .from('dogs')
        .update(values)
        .eq('id', dog.id)
        .eq('owner_id', userId)
        .select('id');
    if (rows.isEmpty) throw StateError('No encontramos ese perfil.');

    if (photoUrl != null) {
      await _client.from('dog_photos').delete().eq('dog_id', dog.id);
      await _client.from('dog_photos').insert({
        'dog_id': dog.id,
        'url': photoUrl,
        'position': 0,
      });
    }
    await _saveHealthRecords(dog.id, dog, userId);
  }

  @override
  Future<void> deleteDog(String dogId) async {
    final rows = await _client
        .from('dogs')
        .update({'is_deleted': true, 'is_visible': false})
        .eq('id', dogId)
        .eq('owner_id', _userId)
        .select('id');
    if (rows.isEmpty) throw StateError('No encontramos ese perfil.');
  }

  @override
  Future<String?> swipe(
    String dogId, {
    String? sourceDogId,
    required bool liked,
    bool superLike = false,
  }) async {
    final myDogs = await _myDogIds();
    if (myDogs.isEmpty) {
      throw StateError('Primero registra el perfil de tu perro.');
    }
    final result = await _client.rpc(
      'swipe',
      params: {
        'p_dog_id': sourceDogId ?? myDogs.first,
        'p_target_dog_id': dogId,
        'p_action': liked ? (superLike ? 'super_like' : 'like') : 'pass',
        'p_message': null,
      },
    );
    return _checkRpcResult(result);
  }

  @override
  Future<String?> sendRequest(Dog dog) async {
    final myDogs = await _myDogIds();
    if (myDogs.isEmpty) {
      throw StateError('Primero registra el perfil de tu perro.');
    }
    final sourceDogId =
        dog.sourceDogId != null && myDogs.contains(dog.sourceDogId)
        ? dog.sourceDogId!
        : myDogs.first;
    final ownDog = await dogById(sourceDogId);
    final result = await _client.rpc(
      'swipe',
      params: {
        'p_dog_id': sourceDogId,
        'p_target_dog_id': dog.id,
        'p_action': 'like',
        'p_message': ownDog == null
            ? null
            : '${ownDog.name} y ${dog.name} podrían conocerse.',
      },
    );
    return _checkRpcResult(result);
  }

  @override
  Future<List<String>> likedDogs() async {
    final ownIds = await _myDogIds();
    if (ownIds.isEmpty) return [];
    final rows = await _client
        .from('swipes')
        .select('target_dog_id')
        .inFilter('swiper_dog_id', ownIds)
        .inFilter('action', ['like', 'super_like']);
    return rows.map((row) => row['target_dog_id'].toString()).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> matches() async {
    final rows = await _client
        .from('matches')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false);
    if (rows.isEmpty) return [];
    final matches = List<Map<String, dynamic>>.from(rows);
    // Match rows contain dog ids, never user ids. Resolve the current owner's
    // dogs once to determine which side of each match belongs to this account.
    final myIds = (await _myDogIds()).toSet();
    final counterpartIds = <String>{};
    for (final row in matches) {
      final a = row['dog_a_id'].toString();
      final b = row['dog_b_id'].toString();
      counterpartIds.add(myIds.contains(a) ? b : a);
    }
    final otherDogs = await _dogsByIds(counterpartIds.toList());
    final dogsById = {for (final dog in otherDogs) dog.id: dog};
    final matchIds = matches.map((row) => row['id'].toString()).toList();
    final conversations = await _client
        .from('conversations')
        .select('id,match_id')
        .inFilter('match_id', matchIds);
    final conversationByMatch = {
      for (final row in conversations)
        row['match_id'].toString(): row['id'].toString(),
    };
    final conversationIds = conversationByMatch.values.toSet().toList();
    final messageRows = conversationIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _client
                .from('messages')
                .select('conversation_id,body,sent_at,read_at,sender_user_id')
                .inFilter('conversation_id', conversationIds)
                .order('sent_at', ascending: false),
          );
    final latestByConversation = <String, Map<String, dynamic>>{};
    var unreadByConversation = <String, int>{};
    for (final row in messageRows) {
      final conversationId = row['conversation_id'].toString();
      latestByConversation.putIfAbsent(conversationId, () => row);
      if (row['sender_user_id'] != _userId && row['read_at'] == null) {
        unreadByConversation.update(
          conversationId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final row in matches) {
      final a = row['dog_a_id'].toString();
      final b = row['dog_b_id'].toString();
      final otherId = myIds.contains(a) ? b : a;
      final dog = dogsById[otherId];
      if (dog == null) continue;
      final conversationId = conversationByMatch[row['id'].toString()];
      final lastMessage = conversationId == null
          ? null
          : latestByConversation[conversationId];
      result.add({
        'matchId': row['id'].toString(),
        'dogId': dog.id,
        'name': dog.name,
        'lastMessage': lastMessage?['body'] ?? '¡Ya hicieron match!',
        'time': _relativeTime(
          _parseDate(lastMessage?['sent_at'] ?? row['created_at']),
        ),
        'unread': conversationId == null
            ? 0
            : (unreadByConversation[conversationId] ?? 0),
      });
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> requests() async {
    final ownDogIds = await _myDogIds();
    final sentRows = await _client
        .from('breeding_requests')
        .select()
        .eq('requester_user_id', _userId)
        .order('created_at', ascending: false);
    final receivedRows = ownDogIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _client
                .from('breeding_requests')
                .select()
                .inFilter('target_dog_id', ownDogIds)
                .order('created_at', ascending: false),
          );
    final counterparts = <String>{
      ...sentRows.map((row) => row['target_dog_id'].toString()),
      ...receivedRows.map((row) => row['requester_dog_id'].toString()),
    };
    final names = {
      for (final dog in await _dogsByIds(counterparts.toList()))
        dog.id: dog.name,
    };
    final result = <Map<String, dynamic>>[];
    for (final row in sentRows) {
      final id = row['target_dog_id'].toString();
      result.add(_requestItem(row, id, names[id], 'sent'));
    }
    for (final row in receivedRows) {
      final id = row['requester_dog_id'].toString();
      result.add(_requestItem(row, id, names[id], 'received'));
    }
    result.sort(
      (a, b) => _parseDate(b['_sortAt']).compareTo(_parseDate(a['_sortAt'])),
    );
    for (final item in result) {
      item.remove('_sortAt');
    }
    return result;
  }

  Map<String, dynamic> _requestItem(
    Map<String, dynamic> row,
    String dogId,
    String? name,
    String direction,
  ) => {
    'requestId': row['id'].toString(),
    'dogId': dogId,
    'name': name ?? 'Perfil',
    'status': row['status'],
    'direction': direction,
    'message': row['message'],
    'time': _relativeTime(_parseDate(row['created_at'])),
    '_sortAt': row['created_at'],
  };

  @override
  Future<void> answerRequest(String requestId, {required bool accept}) async {
    try {
      final result = await _client.rpc(
        'respond_breeding_request',
        params: {'p_request_id': requestId, 'p_accept': accept},
      );
      _checkRpcResult(result);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') {
        throw StateError(
          'Falta instalar respond_breeding_request en Supabase. Ejecuta la '
          'migración 20261124_breeding_request_responses.sql.',
        );
      }
      if (error.code == '42501') {
        throw StateError(
          'Supabase no permite responder solicitudes. Revisa el permiso '
          'EXECUTE de respond_breeding_request para authenticated.',
        );
      }
      throw StateError(
        'Supabase no pudo responder la solicitud '
        '(${error.code ?? 'sin código'}): ${error.message}',
      );
    }
  }

  @override
  Future<List<ChatMessage>> messages(String dogId) async {
    final conversation = await _conversationForDog(dogId);
    if (conversation == null) return [];
    return _messagesForConversation(conversation['id'].toString());
  }

  @override
  Stream<ChatUpdate> watchChat(String dogId) async* {
    final conversation = await _conversationForDog(dogId);
    if (conversation == null) {
      yield const ChatUpdate(messages: []);
      return;
    }
    final conversationId = conversation['id'].toString();
    final updates = StreamController<ChatUpdate>();
    var latestMessages = <ChatMessage>[];
    var otherUserTyping = false;
    Timer? otherTypingTimeout;
    Timer? realtimeFallback;

    Future<void> refreshMessages() async {
      try {
        latestMessages = await _messagesForConversation(conversationId);
        if (!updates.isClosed) {
          updates.add(
            ChatUpdate(
              messages: latestMessages,
              otherUserTyping: otherUserTyping,
            ),
          );
        }
      } catch (error, stackTrace) {
        if (!updates.isClosed) updates.addError(error, stackTrace);
      }
    }

    void startRealtimeFallback() {
      realtimeFallback ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refreshMessages()),
      );
    }

    final channel = _client.channel(
      'tindog:chat:$conversationId',
      opts: const RealtimeChannelConfig(
        private: true,
        ack: true,
        replicationReady: true,
      ),
    );
    _chatChannelsByDog[dogId] = channel;
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => unawaited(refreshMessages()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => unawaited(refreshMessages()),
        )
        .onBroadcast(
          event: 'message',
          callback: (_) => unawaited(refreshMessages()),
        )
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (payload['user_id']?.toString() == _userId) return;
            otherUserTyping = payload['typing'] == true;
            otherTypingTimeout?.cancel();
            if (otherUserTyping) {
              otherTypingTimeout = Timer(const Duration(seconds: 5), () {
                otherUserTyping = false;
                if (!updates.isClosed) {
                  updates.add(
                    ChatUpdate(
                      messages: latestMessages,
                      otherUserTyping: false,
                    ),
                  );
                }
              });
            }
            if (!updates.isClosed) {
              updates.add(
                ChatUpdate(
                  messages: latestMessages,
                  otherUserTyping: otherUserTyping,
                ),
              );
            }
          },
        )
        .onSystemEvents((payload) {
          if (payload is Map &&
              payload['extension'] == 'system' &&
              payload['status'] == 'error' &&
              !updates.isClosed) {
            startRealtimeFallback();
            updates.addError(
              StateError(
                'Supabase Realtime no pudo escuchar mensajes. Revisa que '
                'public.messages esté en la publicación supabase_realtime.',
              ),
            );
          }
        })
        .subscribe((status, error) {
          if (updates.isClosed) return;
          if (status == RealtimeSubscribeStatus.subscribed) {
            realtimeFallback?.cancel();
            realtimeFallback = null;
            final pendingTyping = _pendingTypingByDog.remove(dogId);
            if (pendingTyping != null) {
              unawaited(_sendTyping(channel, pendingTyping));
            }
            unawaited(refreshMessages());
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            startRealtimeFallback();
            if (!updates.isClosed) {
              updates.addError(
                StateError(
                  'No se pudo conectar al chat en tiempo real: '
                  '${error ?? status.name}.',
                ),
              );
            }
          }
        });

    unawaited(refreshMessages());
    try {
      await for (final update in updates.stream) {
        yield update;
      }
    } finally {
      otherTypingTimeout?.cancel();
      realtimeFallback?.cancel();
      if (identical(_chatChannelsByDog[dogId], channel)) {
        _chatChannelsByDog.remove(dogId);
      }
      _pendingTypingByDog.remove(dogId);
      await updates.close();
      await _client.removeChannel(channel);
    }
  }

  @override
  Future<void> setTyping(String dogId, bool isTyping) async {
    final channel = _chatChannelsByDog[dogId];
    if (channel == null || !channel.canPush) {
      _pendingTypingByDog[dogId] = isTyping;
      return;
    }
    await _sendTyping(channel, isTyping);
  }

  Future<void> _sendTyping(RealtimeChannel channel, bool isTyping) async {
    final result = await channel.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': _userId, 'typing': isTyping},
    );
    if (result != ChannelResponse.ok) {
      throw StateError('Supabase no recibió el indicador de escritura.');
    }
  }

  Future<List<ChatMessage>> _messagesForConversation(
    String conversationId,
  ) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('sent_at');
    if (rows.any(
      (row) => row['sender_user_id'] != _userId && row['read_at'] == null,
    )) {
      await _markRead(conversationId);
    }
    return rows.map((row) => _messageFromRow(row)).toList();
  }

  @override
  Future<void> sendMessage(String dogId, ChatMessage message) async {
    final conversation = await _conversationForDog(dogId);
    if (conversation == null) {
      throw StateError('No hay una conversación activa con este perfil.');
    }
    await _client.from('messages').insert({
      'conversation_id': conversation['id'],
      'sender_user_id': _userId,
      'body': message.text,
    });
    final channel = _chatChannelsByDog[dogId];
    if (channel != null && channel.canPush) {
      try {
        final response = await channel
            .sendBroadcastMessage(
              event: 'message',
              payload: {'sender_user_id': _userId},
            )
            .timeout(const Duration(seconds: 2));
        if (response != ChannelResponse.ok) {
          debugPrint('TinDog chat: no se recibió el ACK de Realtime.');
        }
      } catch (error) {
        debugPrint('TinDog chat: no se pudo emitir el aviso realtime: $error');
      }
    }
  }

  @override
  Future<void> clearConversation(String dogId) async {
    throw StateError(
      'La base de datos no permite borrar mensajes desde la app.',
    );
  }

  Future<void> _markRead(String conversationId) async {
    await _client
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .neq('sender_user_id', _userId);
  }

  Future<Map<String, dynamic>?> _conversationForDog(String dogId) async {
    final cached = _conversationsByDog[dogId];
    if (cached != null) return cached;
    final ownIds = (await _myDogIds()).toSet();
    if (ownIds.isEmpty) return null;
    final matches = await _client
        .from('matches')
        .select('id,dog_a_id,dog_b_id')
        .eq('status', 'active')
        .order('created_at', ascending: false);
    for (final match in matches) {
      final a = match['dog_a_id'].toString();
      final b = match['dog_b_id'].toString();
      final otherDogId = ownIds.contains(a) ? b : a;
      if (otherDogId != dogId) continue;
      final rows = await _client
          .from('conversations')
          .select('id,match_id')
          .eq('match_id', match['id'])
          .limit(1);
      if (rows.isNotEmpty) {
        final conversation = Map<String, dynamic>.from(rows.first);
        _conversationsByDog[dogId] = conversation;
        return conversation;
      }
    }
    return null;
  }

  Future<List<Dog>> _dogsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client.from('dogs').select().inFilter('id', ids);
    return _hydrateDogs(List<Map<String, dynamic>>.from(rows));
  }

  Future<List<Dog>> _hydrateDogs(
    List<Map<String, dynamic>> rows, {
    Map<String, int> distanceByDogId = const {},
  }) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((row) => row['id'].toString()).toSet().toList();
    final breedIds = rows
        .expand((row) => [row['breed_id'], row['secondary_breed_id']])
        .whereType<num>()
        .map((id) => id.toInt())
        .toSet()
        .toList();
    final ownerIds = rows
        .map((row) => row['owner_id'].toString())
        .toSet()
        .toList();

    final breedRows = breedIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _optionalRows(
            () async => await _client
                .from('breeds')
                .select('id,name')
                .inFilter('id', breedIds),
          );
    final breeds = {
      for (final row in breedRows) row['id'].toString(): row['name'].toString(),
    };
    final photoRows = await _optionalRows(
      () async => await _client
          .from('dog_photos')
          .select('dog_id,url,position')
          .inFilter('dog_id', ids)
          .order('position'),
    );
    final photos = <String, List<String>>{};
    for (final row in photoRows) {
      final photoUrl = await _resolvePhotoUrl(row['url'].toString());
      if (photoUrl == null) continue;
      photos.putIfAbsent(row['dog_id'].toString(), () => []).add(photoUrl);
    }
    final healthRows = await _optionalRows(
      () async => await _client
          .from('dog_health_status')
          .select('dog_id,kind,name,expires_on,status')
          .inFilter('dog_id', ids),
    );
    final vaccines = <String, Map<String, String>>{};
    for (final row in healthRows) {
      if (row['kind'] != 'vaccine' ||
          row['name'] == null ||
          row['expires_on'] == null) {
        continue;
      }
      vaccines.putIfAbsent(row['dog_id'].toString(), () => {})[row['name']
          .toString()] = row['expires_on']
          .toString();
    }
    final healthTypeRows = await _optionalRows(
      () async =>
          await _client.from('health_item_types').select('id,name,kind'),
    );
    final healthTypeNames = {
      for (final row in healthTypeRows)
        row['id'].toString(): row['name'].toString(),
    };
    final healthRecordRows = await _optionalRows(
      () async => await _client
          .from('dog_health_records')
          .select(
            'dog_id,type_id,applied_on,expires_on,product_name,lot_number,label_photo_url,verification_status',
          )
          .inFilter('dog_id', ids)
          .order('created_at', ascending: false),
    );
    final appliedDates = <String, Map<String, String>>{};
    final healthLabels = <String, Map<String, String>>{};
    final vaccineProducts = <String, Map<String, String>>{};
    final vaccineLots = <String, Map<String, String>>{};
    final recordExpirations = <String, Map<String, String>>{};
    for (final record in healthRecordRows) {
      final dogId = record['dog_id'].toString();
      final name = healthTypeNames[record['type_id'].toString()];
      if (name == null) continue;
      final appliedOn = record['applied_on']?.toString();
      if (appliedOn != null) {
        appliedDates
            .putIfAbsent(dogId, () => {})
            .putIfAbsent(name, () => appliedOn);
      }
      final productName = record['product_name']?.toString().trim();
      if (productName != null && productName.isNotEmpty) {
        vaccineProducts
            .putIfAbsent(dogId, () => {})
            .putIfAbsent(name, () => productName);
      }
      final lotNumber = record['lot_number']?.toString().trim();
      if (lotNumber != null && lotNumber.isNotEmpty) {
        vaccineLots
            .putIfAbsent(dogId, () => {})
            .putIfAbsent(name, () => lotNumber);
      }
      final expiresOn = record['expires_on']?.toString();
      if (expiresOn != null) {
        recordExpirations
            .putIfAbsent(dogId, () => {})
            .putIfAbsent(name, () => expiresOn);
      }
      final labelPath = record['label_photo_url']?.toString();
      if (labelPath != null) {
        final resolved = await _resolveStorageUrl(
          _healthLabelBucket,
          labelPath,
        );
        if (resolved != null) {
          healthLabels
              .putIfAbsent(dogId, () => {})
              .putIfAbsent(name, () => resolved);
        }
      }
    }
    for (final entry in recordExpirations.entries) {
      vaccines.putIfAbsent(entry.key, () => {}).addAll(entry.value);
    }
    final userRows = await _optionalRows(
      () async => await _client
          .from('users')
          .select('id,city')
          .inFilter('id', ownerIds),
    );
    final cities = {
      for (final row in userRows) row['id'].toString(): row['city'] as String?,
    };

    return rows.map((row) {
      final id = row['id'].toString();
      final primaryBreed = breeds[row['breed_id']?.toString()];
      final secondaryBreed = breeds[row['secondary_breed_id']?.toString()];
      final isMixed = row['is_mixed'] == true;
      final breedName = isMixed
          ? 'Mestizo'
          : [
              primaryBreed,
              secondaryBreed,
            ].whereType<String>().where((name) => name.isNotEmpty).join(' / ');
      final birthDate = DateTime.tryParse(row['birth_date']?.toString() ?? '');
      final health = vaccines[id] ?? const <String, String>{};
      final photoList = photos[id] ?? const <String>[];
      final sex = switch (row['sex']) {
        'female' => 'Hembra',
        'male' => 'Macho',
        _ => row['sex']?.toString() ?? '',
      };
      final distance = distanceByDogId[id];
      return Dog(
        id: id,
        name: row['name']?.toString() ?? '',
        breed: breedName.isEmpty ? 'Raza no especificada' : breedName,
        age: _ageInYears(birthDate),
        intention: row['primary_intention']?.toString() ?? 'playdate',
        birthDate: birthDate,
        sex: sex,
        location:
            cities[row['owner_id']?.toString()] ??
            (distance == null ? 'Ubicación no disponible' : 'GPS'),
        distanceKm: distance,
        compatibility: null,
        vaccines: health,
        vaccineAppliedOn: appliedDates[id] ?? const {},
        vaccineLabelPhotos: healthLabels[id] ?? const {},
        vaccineProducts: vaccineProducts[id] ?? const {},
        vaccineLots: vaccineLots[id] ?? const {},
        photo: photoList.isEmpty ? '' : photoList.first,
        about: row['bio']?.toString() ?? '',
        color: '#FFDCCB',
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _optionalRows(
    Future<List<Map<String, dynamic>>> Function() query,
  ) async {
    try {
      return await query();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> _dogToRow(Dog dog) async {
    final mixed = const {
      'mestizo',
      'mixto',
    }.contains(dog.breed.trim().toLowerCase());
    final breedRows = dog.breed.trim().isEmpty || mixed
        ? <Map<String, dynamic>>[]
        : await _optionalRows(
            () async => await _client
                .from('breeds')
                .select('id')
                .ilike('name', dog.breed.trim())
                .limit(1),
          );
    final breedId = breedRows.isEmpty ? null : breedRows.first['id'];
    if (breedId == null && !mixed) {
      throw StateError(
        'La raza debe coincidir con el cat\u00e1logo. Si es mestizo, escribe Mestizo.',
      );
    }
    final birthDate =
        dog.birthDate ?? DateTime(DateTime.now().year - dog.age, 1, 1);
    return {
      'name': dog.name.trim(),
      'sex': _dbSex(dog.sex),
      'birth_date': _dateOnly(birthDate),
      'breed_id': breedId,
      'secondary_breed_id': null,
      'is_mixed': mixed,
      'size': null,
      'weight_kg': null,
      'energy_level': null,
      'is_neutered': false,
      'primary_intention':
          const {'breeding', 'playdate'}.contains(dog.intention)
          ? dog.intention
          : 'playdate',
      'secondary_intention': null,
      'bio': dog.about.trim(),
      'is_visible': true,
      'is_deleted': false,
    };
  }

  Future<void> _saveHealthRecords(String dogId, Dog dog, String userId) async {
    final vaccineNames = <String>{
      ...dog.vaccines.keys,
      ...dog.vaccineAppliedOn.keys,
      ...dog.vaccineLabelPhotos.keys,
      ...dog.vaccineProducts.keys,
      ...dog.vaccineLots.keys,
    };
    if (vaccineNames.isEmpty) return;

    final types = await _client
        .from('health_item_types')
        .select('id,name,kind')
        .eq('kind', 'vaccine');
    final typeIds = {
      for (final row in types)
        row['name'].toString().trim().toLowerCase(): row['id'],
    };
    for (final name in vaccineNames) {
      final normalizedName = name.trim().toLowerCase();
      final typeId =
          typeIds[normalizedName] ??
          (normalizedName == 'parvovirus / moquillo'
              ? typeIds['parvovirus']
              : null);
      if (typeId == null) {
        throw StateError(
          'La vacuna "$name" no existe en public.health_item_types. '
          'Revisa el catálogo de vacunas en Supabase.',
        );
      }
      final appliedOn = dog.vaccineAppliedOn[name];
      final expiresOn = dog.vaccines[name];
      final productName = dog.vaccineProducts[name]?.trim();
      final lotNumber = dog.vaccineLots[name]?.trim();
      final photoValue = dog.vaccineLabelPhotos[name];
      final hasAnyData =
          appliedOn != null ||
          expiresOn != null ||
          (productName?.isNotEmpty ?? false) ||
          (lotNumber?.isNotEmpty ?? false) ||
          (photoValue?.isNotEmpty ?? false);
      if (!hasAnyData) continue;
      if (appliedOn == null) {
        throw StateError('Selecciona la fecha de aplicación de $name.');
      }

      final existing = await _client
          .from('dog_health_records')
          .select(
            'id,verification_status,label_photo_url,applied_on,expires_on,product_name,lot_number',
          )
          .eq('dog_id', dogId)
          .eq('type_id', typeId)
          .order('created_at', ascending: false)
          .limit(1);
      final currentRecord = existing.isEmpty ? null : existing.first;
      final isApproved = currentRecord?['verification_status'] == 'approved';
      final photoChanged = photoValue?.startsWith('picked:') == true;
      String? savedText(String column) {
        final value = currentRecord?[column]?.toString().trim();
        return value?.isEmpty == true ? null : value;
      }

      final sameSavedData =
          currentRecord != null &&
          currentRecord['applied_on']?.toString() == appliedOn &&
          currentRecord['expires_on']?.toString() == expiresOn &&
          savedText('product_name') ==
              (productName?.isEmpty == true ? null : productName) &&
          savedText('lot_number') ==
              (lotNumber?.isEmpty == true ? null : lotNumber);
      if (sameSavedData && !photoChanged) continue;
      if (isApproved && dog.intention == 'breeding' && !photoChanged) {
        throw StateError(
          'El registro aprobado de $name no se modifica. Para registrar una '
          'nueva dosis de cruza, selecciona una foto nueva de su etiqueta.',
        );
      }

      String? labelPath = isApproved
          ? null
          : currentRecord?['label_photo_url']?.toString();
      if (photoValue != null && photoValue.startsWith('picked:')) {
        final localPath = photoValue.substring('picked:'.length);
        final file = File(localPath);
        final fileName = file.uri.pathSegments.isEmpty
            ? 'label.jpg'
            : file.uri.pathSegments.last;
        final extension = fileName.toLowerCase().endsWith('.png')
            ? 'png'
            : 'jpg';
        final uploadedPath =
            '$userId/$dogId/${typeId}_${DateTime.now().microsecondsSinceEpoch}.$extension';
        labelPath = uploadedPath;
        await _client.storage
            .from(_healthLabelBucket)
            .uploadBinary(
              uploadedPath,
              await file.readAsBytes(),
              fileOptions: FileOptions(
                cacheControl: '3600',
                contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
                upsert: false,
              ),
            );
      } else if (!isApproved &&
          photoValue != null &&
          photoValue.trim().isNotEmpty &&
          (labelPath == null || labelPath.isEmpty)) {
        labelPath = photoValue.trim();
      }

      if (currentRecord != null && !isApproved) {
        final deleted = await _client
            .from('dog_health_records')
            .delete()
            .eq('id', currentRecord['id'])
            .select('id');
        if (deleted.isEmpty) {
          throw StateError(
            'Supabase no permitió actualizar la vacuna $name. Revisa la '
            'política DELETE de dog_health_records para registros pendientes.',
          );
        }
      }
      await _client.from('dog_health_records').insert({
        'dog_id': dogId,
        'type_id': typeId,
        'applied_on': appliedOn,
        'expires_on': expiresOn,
        'product_name': productName?.isEmpty == true ? null : productName,
        'lot_number': lotNumber?.isEmpty == true ? null : lotNumber,
        'label_photo_url': labelPath,
        'verification_status': 'pending',
      });
    }
  }

  Future<String?> _photoUrlFor(Dog dog, String dogId, String userId) async {
    if (!dog.photo.startsWith('picked:')) {
      return dog.photo.startsWith('https://') || dog.photo.startsWith('http://')
          ? dog.photo
          : null;
    }
    final file = File(dog.photo.substring('picked:'.length));
    final fileName = file.uri.pathSegments.isEmpty
        ? 'photo.jpg'
        : file.uri.pathSegments.last;
    final extension = fileName.toLowerCase().endsWith('.png')
        ? 'png'
        : fileName.toLowerCase().endsWith('.webp')
        ? 'webp'
        : 'jpg';
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '$userId/$dogId.$extension';
    await _client.storage
        .from(_photoBucket)
        .uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: contentType,
            upsert: true,
          ),
        );
    return path;
  }

  Future<String?> _resolvePhotoUrl(String value) async {
    return _resolveStorageUrl(_photoBucket, value);
  }

  Future<String?> _resolveStorageUrl(String bucket, String value) async {
    if (value.startsWith('https://') || value.startsWith('http://')) {
      return value;
    }
    if (value.isEmpty) return null;
    try {
      return await _client.storage
          .from(bucket)
          .createSignedUrl(value, 60 * 60 * 24);
    } catch (_) {
      return null;
    }
  }

  ChatMessage _messageFromRow(Map<String, dynamic> row) {
    final sentAt = _parseDate(row['sent_at']).toLocal();
    return ChatMessage(
      text: row['body']?.toString() ?? '',
      mine: row['sender_user_id'] == _userId,
      time:
          '${sentAt.hour.toString().padLeft(2, '0')}:${sentAt.minute.toString().padLeft(2, '0')}',
      read: row['read_at'] != null,
    );
  }

  String? _checkRpcResult(dynamic result) {
    if (result is Map && result['ok'] == false) {
      final error = result['error']?.toString() ?? 'request_failed';
      throw StateError(_rpcErrorMessage(error));
    }
    return result is Map ? result['result']?.toString() : null;
  }

  String _rpcErrorMessage(String error) => switch (error) {
    'not_authenticated' => 'Inicia sesión para continuar.',
    'dog_not_owned' => 'El perfil de tu perro no te pertenece.',
    'target_not_found' => 'Este perfil ya no está disponible.',
    'already_swiped' => 'Ya habías indicado interés en este perfil.',
    'not_eligible' => 'Este perfil no cumple los requisitos para conectar.',
    'daily_limit_reached' => 'Llegaste al límite diario de solicitudes.',
    'pending_limit_reached' => 'Tienes demasiadas solicitudes pendientes.',
    'request_not_found' => 'La solicitud ya no está disponible.',
    'request_not_pending' => 'Esta solicitud ya fue respondida.',
    'request_expired' => 'Esta solicitud ya venció.',
    'my_dog_paused' => 'Activa el perfil de tu perro para aceptar.',
    'my_health_required' =>
      'Actualiza primero la cartilla de salud de tu perro.',
    'request_cancelled' => 'La solicitud dejó de ser válida.',
    _ => 'No se pudo completar la acción ($error).',
  };

  String _dbSex(String value) => switch (value.toLowerCase()) {
    'hembra' || 'female' => 'female',
    'macho' || 'male' => 'male',
    _ => value.toLowerCase(),
  };

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  int _ageInYears(DateTime? birthDate) {
    if (birthDate == null) return 0;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return max(0, age);
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  DateTime _parseDate(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

  String _relativeTime(DateTime date) {
    final difference = DateTime.now().difference(date.toLocal());
    if (difference.inMinutes < 1) return 'Ahora';
    if (difference.inHours < 1) return 'Hace ${difference.inMinutes} min';
    if (difference.inDays < 1) return 'Hace ${difference.inHours} h';
    if (difference.inDays == 1) return 'Ayer';
    return 'Hace ${difference.inDays} días';
  }
}

class _CandidateHealthData {
  final vaccines = <String, String>{};
  final appliedOn = <String, String>{};
  final products = <String, String>{};
  final lots = <String, String>{};
}
