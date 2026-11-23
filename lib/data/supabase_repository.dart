import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dog.dart';
import 'repository.dart';

class SupabaseTinDogRepository implements TinDogRepository {
  SupabaseTinDogRepository(this._client);

  final SupabaseClient _client;
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
  bool get supportsDistanceFilter => false;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Inicia sesiÃ³n para continuar.');
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
      final identities = response.user?.identities;
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
      if (message.contains('already registered') ||
          message.contains('already been registered') ||
          message.contains('user exists')) {
        return RegistrationResult.alreadyRegistered;
      }
      if (message.contains('rate limit') ||
          message.contains('too many requests')) {
        throw StateError(
          'Supabase limito los correos de registro. Espera un momento o inicia sesion con una cuenta existente.',
        );
      }
      if (message.contains('signup is disabled') ||
          message.contains('signups not allowed')) {
        throw StateError(
          'El registro de cuentas esta desactivado en Supabase.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() => _client.auth.signOut();

  Future<List<String>> _myDogIds() async {
    final rows = await _client
        .from('dogs')
        .select('id')
        .eq('owner_id', _userId)
        .eq('is_deleted', false);
    return rows.map((row) => row['id'].toString()).toList();
  }

  @override
  Future<List<Dog>> discoverDogs() async {
    final ownIds = (await _myDogIds()).toSet();
    final seenIds = <String>{};
    if (ownIds.isNotEmpty) {
      final swipes = await _client
          .from('swipes')
          .select('target_dog_id')
          .inFilter('swiper_dog_id', ownIds.toList());
      seenIds.addAll(swipes.map((row) => row['target_dog_id'].toString()));
    }

    final rows = await _client
        .from('dogs')
        .select()
        .eq('is_visible', true)
        .eq('is_deleted', false)
        .order('created_at', ascending: false);
    final candidates = rows
        .where(
          (row) =>
              !ownIds.contains(row['id'].toString()) &&
              !seenIds.contains(row['id'].toString()),
        )
        .toList();
    return _hydrateDogs(candidates);
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
    await _savePedigree(id, dog);
    await _saveHealthRecords(id, dog, userId);
  }

  @override
  Future<void> updateDog(Dog dog) async {
    final userId = _userId;
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
    await _savePedigree(dog.id, dog);
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
        'p_dog_id': myDogs.first,
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
    final ownDog = await dogById(myDogs.first);
    final result = await _client.rpc(
      'swipe',
      params: {
        'p_dog_id': myDogs.first,
        'p_target_dog_id': dog.id,
        'p_action': 'like',
        'p_message': ownDog == null
            ? null
            : '${ownDog.name} y ${dog.name} podrÃ­an conocerse.',
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
        'lastMessage': lastMessage?['body'] ?? 'Â¡Ya hicieron match!',
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
    final result = await _client.rpc(
      'respond_breeding_request',
      params: {'p_request_id': requestId, 'p_accept': accept},
    );
    _checkRpcResult(result);
  }

  @override
  Future<List<ChatMessage>> messages(String dogId) async {
    final conversation = await _conversationForDog(dogId);
    if (conversation == null) return [];
    final rows = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversation['id'])
        .order('sent_at');
    await _markRead(conversation['id'].toString());
    return rows.map((row) => _messageFromRow(row)).toList();
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String dogId) async* {
    final conversation = await _conversationForDog(dogId);
    if (conversation == null) {
      yield const [];
      return;
    }
    yield await messages(dogId);
    yield* _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversation['id'])
        .order('sent_at')
        .map((rows) {
          if (rows.any(
            (row) => row['sender_user_id'] != _userId && row['read_at'] == null,
          )) {
            unawaited(_markRead(conversation['id'].toString()));
          }
          return rows.map(_messageFromRow).toList();
        });
  }

  @override
  Future<void> sendMessage(String dogId, ChatMessage message) async {
    final conversation = await _conversationForDog(dogId);
    if (conversation == null) {
      throw StateError('No hay una conversaciÃ³n activa con este perfil.');
    }
    await _client.from('messages').insert({
      'conversation_id': conversation['id'],
      'sender_user_id': _userId,
      'body': message.text,
    });
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
      if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
    }
    return null;
  }

  Future<List<Dog>> _dogsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client.from('dogs').select().inFilter('id', ids);
    return _hydrateDogs(List<Map<String, dynamic>>.from(rows));
  }

  Future<List<Dog>> _hydrateDogs(List<Map<String, dynamic>> rows) async {
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
    final pedigreeRows = await _optionalRows(
      () async => await _client
          .from('dog_pedigrees')
          .select('dog_id,registration_number,verification_status')
          .inFilter('dog_id', ids),
    );
    final verifiedRows = await _optionalRows(
      () async => await _client
          .from('dog_verified_pedigree')
          .select('dog_id')
          .inFilter('dog_id', ids),
    );
    final pedigrees = <String, Map<String, dynamic>>{};
    for (final row in pedigreeRows) {
      pedigrees[row['dog_id'].toString()] = row;
    }
    final verified = verifiedRows
        .map((row) => row['dog_id'].toString())
        .toSet();
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
            'dog_id,type_id,applied_on,expires_on,label_photo_url,verification_status',
          )
          .inFilter('dog_id', ids),
    );
    final appliedDates = <String, Map<String, String>>{};
    final healthLabels = <String, Map<String, String>>{};
    for (final record in healthRecordRows) {
      final dogId = record['dog_id'].toString();
      final name = healthTypeNames[record['type_id'].toString()];
      if (name == null) continue;
      final appliedOn = record['applied_on']?.toString();
      if (appliedOn != null) {
        appliedDates.putIfAbsent(dogId, () => {})[name] = appliedOn;
      }
      final expiresOn = record['expires_on']?.toString();
      if (expiresOn != null) {
        vaccines
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
          healthLabels.putIfAbsent(dogId, () => {})[name] = resolved;
        }
      }
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
      final pedigree = pedigrees[id];
      final approved =
          verified.contains(id) ||
          pedigree?['verification_status'] == 'approved';
      final health = vaccines[id] ?? const <String, String>{};
      final photoList = photos[id] ?? const <String>[];
      final sex = switch (row['sex']) {
        'female' => 'Hembra',
        'male' => 'Macho',
        _ => row['sex']?.toString() ?? '',
      };
      return Dog(
        id: id,
        name: row['name']?.toString() ?? '',
        breed: breedName.isEmpty ? 'Raza no especificada' : breedName,
        age: _ageInYears(birthDate),
        intention: row['primary_intention']?.toString() ?? 'playdate',
        birthDate: birthDate,
        sex: sex,
        location:
            cities[row['owner_id']?.toString()] ?? 'UbicaciÃ³n no disponible',
        distanceKm: null,
        compatibility: null,
        pedigree: approved,
        hasPedigree: approved || pedigree != null,
        pedigreeNumber: pedigree?['registration_number']?.toString() ?? '',
        vaccines: health,
        vaccineAppliedOn: appliedDates[id] ?? const {},
        vaccineLabelPhotos: healthLabels[id] ?? const {},
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
        'La raza debe coincidir con el catalogo. Si es mestizo, escribe Mestizo.',
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

  Future<void> _savePedigree(String dogId, Dog dog) async {
    final rows = await _client
        .from('dog_pedigrees')
        .select('verification_status,registration_number')
        .eq('dog_id', dogId)
        .limit(1);
    final existing = rows.isEmpty ? null : rows.first;
    if (existing?['verification_status'] == 'approved') return;

    if (!dog.hasPedigree || dog.pedigreeNumber.trim().isEmpty) {
      if (existing != null) {
        await _client.from('dog_pedigrees').delete().eq('dog_id', dogId);
      }
      return;
    }
    if (existing?['registration_number'] == dog.pedigreeNumber.trim()) return;
    if (existing != null) {
      await _client.from('dog_pedigrees').delete().eq('dog_id', dogId);
    }
    await _client.from('dog_pedigrees').insert({
      'dog_id': dogId,
      'registry': 'FCM',
      'registration_number': dog.pedigreeNumber.trim(),
      'verification_status': 'pending',
    });
  }

  Future<void> _saveHealthRecords(String dogId, Dog dog, String userId) async {
    final records = dog.vaccineLabelPhotos.entries
        .where((entry) => entry.value.startsWith('picked:'))
        .toList();
    if (records.isEmpty) return;

    final types = await _client
        .from('health_item_types')
        .select('id,name,kind')
        .eq('kind', 'vaccine');
    final typeIds = {
      for (final row in types)
        row['name'].toString().trim().toLowerCase(): row['id'],
    };
    for (final record in records) {
      final typeId = typeIds[record.key.trim().toLowerCase()];
      final appliedOn = dog.vaccineAppliedOn[record.key];
      final expiresOn = dog.vaccines[record.key];
      if (typeId == null || appliedOn == null) {
        throw StateError('Faltan datos de salud para ${record.key}.');
      }
      final existing = await _client
          .from('dog_health_records')
          .select('id,verification_status')
          .eq('dog_id', dogId)
          .eq('type_id', typeId)
          .limit(1);
      if (existing.isNotEmpty &&
          existing.first['verification_status'] == 'approved') {
        throw StateError(
          'El registro aprobado de ${record.key} no se puede reemplazar desde la app.',
        );
      }

      final localPath = record.value.substring('picked:'.length);
      final file = File(localPath);
      final fileName = file.uri.pathSegments.isEmpty
          ? 'label.jpg'
          : file.uri.pathSegments.last;
      final extension = fileName.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final path =
          '$userId/$dogId/${typeId}_${DateTime.now().microsecondsSinceEpoch}.$extension';
      await _client.storage
          .from(_healthLabelBucket)
          .uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              cacheControl: '3600',
              contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
              upsert: false,
            ),
          );
      if (existing.isNotEmpty) {
        await _client
            .from('dog_health_records')
            .delete()
            .eq('dog_id', dogId)
            .eq('type_id', typeId);
      }
      await _client.from('dog_health_records').insert({
        'dog_id': dogId,
        'type_id': typeId,
        'applied_on': appliedOn,
        'expires_on': expiresOn,
        'label_photo_url': path,
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
    'not_authenticated' => 'Inicia sesiÃ³n para continuar.',
    'dog_not_owned' => 'El perfil de tu perro no te pertenece.',
    'target_not_found' => 'Este perfil ya no estÃ¡ disponible.',
    'already_swiped' => 'Ya habÃ­as indicado interÃ©s en este perfil.',
    'not_eligible' => 'Este perfil no cumple los requisitos para conectar.',
    'daily_limit_reached' => 'Llegaste al lÃ­mite diario de solicitudes.',
    'pending_limit_reached' => 'Tienes demasiadas solicitudes pendientes.',
    'request_not_found' => 'La solicitud ya no estÃ¡ disponible.',
    'request_not_pending' => 'Esta solicitud ya fue respondida.',
    'request_expired' => 'Esta solicitud ya venciÃ³.',
    'my_dog_paused' => 'Activa el perfil de tu perro para aceptar.',
    'my_health_required' =>
      'Actualiza primero la cartilla de salud de tu perro.',
    'request_cancelled' => 'La solicitud dejÃ³ de ser vÃ¡lida.',
    _ => 'No se pudo completar la acciÃ³n ($error).',
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
    return 'Hace ${difference.inDays} dÃ­as';
  }
}
