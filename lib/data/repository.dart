import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dog.dart';

abstract class TinDogRepository {
  Future<String?> restoreSession();
  Future<bool> login(String email, String password);
  Future<bool> register(String name, String email, String password);
  Future<void> logout();
  Future<List<Dog>> discoverDogs();
  Future<void> resetDiscovery();
  Future<Dog?> dogById(String dogId);
  Future<List<Dog>> myDogs();
  Future<void> addDog(Dog dog);
  Future<void> updateDog(Dog dog);
  Future<void> deleteDog(String dogId);
  Future<void> swipe(String dogId, {required bool liked});
  Future<void> sendRequest(Dog dog);
  Future<List<String>> likedDogs();
  Future<List<Map<String, dynamic>>> matches();
  Future<List<Map<String, dynamic>>> requests();
  Future<void> answerRequest(String dogId, {required bool accept});
  Future<List<ChatMessage>> messages(String dogId);
  Future<void> sendMessage(String dogId, ChatMessage message);
  Future<void> clearConversation(String dogId);
}

/// Local implementation. Widgets depend only on TinDogRepository, so this
/// adapter can be replaced by a REST implementation without changing screens.
class LocalTinDogRepository implements TinDogRepository {
  LocalTinDogRepository(this._preferences);

  final SharedPreferences _preferences;
  static const _delay = Duration(milliseconds: 700);
  List<Dog>? _catalog;

  Future<List<Dog>> _loadCatalog() async {
    if (_catalog case final list?) return list;
    final jsonText = await rootBundle.loadString('assets/json/dogs.json');
    _catalog = (jsonDecode(jsonText) as List)
        .cast<Map<String, dynamic>>()
        .map(Dog.fromJson)
        .toList(growable: false);
    return _catalog!;
  }

  List<dynamic> _readList(String key) {
    final raw = _preferences.getString(key);
    if (raw == null) return [];
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeList(String key, List<dynamic> value) =>
      _preferences.setString(key, jsonEncode(value));

  @override
  Future<String?> restoreSession() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return _preferences.getString('sessionEmail');
  }

  @override
  Future<bool> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final savedUsers = _preferences.getString('users') ?? '{}';
    final users = jsonDecode(savedUsers) as Map<String, dynamic>;
    final isDemo =
        email.trim().toLowerCase() == 'demo@tindog.mx' &&
        password == 'Demo1234';
    final isSaved = users[email.trim().toLowerCase()] == password;
    if (isDemo || isSaved) {
      await _preferences.setString('sessionEmail', email.trim().toLowerCase());
      return true;
    }
    return false;
  }

  @override
  Future<bool> register(String name, String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final users = jsonDecode(
      _preferences.getString('users') ?? '{}',
    ) as Map<String, dynamic>;
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail == 'demo@tindog.mx' ||
        users.containsKey(normalizedEmail)) {
      return false;
    }
    users[normalizedEmail] = password;
    await _preferences.setString('users', jsonEncode(users));
    await _preferences.setString('displayName', name.trim());
    await _preferences.setString('sessionEmail', normalizedEmail);
    return true;
  }

  @override
  Future<void> logout() => _preferences.remove('sessionEmail');

  @override
  Future<List<Dog>> discoverDogs() async {
    await Future<void>.delayed(_delay);
    final allDogs = await _loadCatalog();
    final seen = _readList('seenDogs').map((e) => e.toString()).toSet();
    final mine = await myDogs();
    return allDogs
        .where(
          (dog) =>
              !seen.contains(dog.id) &&
              !mine.any((mineDog) => mineDog.id == dog.id),
        )
        .toList();
  }

  @override
  Future<void> resetDiscovery() => _preferences.remove('seenDogs');

  @override
  Future<Dog?> dogById(String dogId) async {
    final local = await myDogs();
    for (final dog in local) {
      if (dog.id == dogId) return dog;
    }
    for (final dog in await _loadCatalog()) {
      if (dog.id == dogId) return dog;
    }
    return null;
  }

  @override
  Future<List<Dog>> myDogs() async {
    final saved = _readList('myDogs')
        .map((value) => Dog.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
    return saved;
  }

  Future<Dog> _storeDogPhoto(Dog dog) async {
    var stored = dog;
    if (dog.photo.startsWith('picked:')) {
      final source = File(dog.photo.substring('picked:'.length));
      final directory = await getApplicationDocumentsDirectory();
      final photoDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}dogs',
      );
      await photoDirectory.create(recursive: true);
      final destination = File(
        '${photoDirectory.path}${Platform.pathSeparator}${dog.id}.jpg',
      );
      await source.copy(destination.path);
      stored = Dog.fromJson({...dog.toJson(), 'photo': destination.path});
    }
    return stored;
  }

  @override
  Future<void> addDog(Dog dog) async {
    final stored = await _storeDogPhoto(dog);
    final dogs = await myDogs();
    dogs.add(stored);
    await _writeList('myDogs', dogs.map((e) => e.toJson()).toList());
  }

  @override
  Future<void> updateDog(Dog dog) async {
    final stored = await _storeDogPhoto(dog);
    final dogs = await myDogs();
    final index = dogs.indexWhere((item) => item.id == dog.id);
    if (index < 0) return;
    dogs[index] = stored;
    await _writeList('myDogs', dogs.map((item) => item.toJson()).toList());
  }

  @override
  Future<void> deleteDog(String dogId) async {
    final dogs = await myDogs();
    final index = dogs.indexWhere((item) => item.id == dogId);
    if (index < 0) return;
    final removed = dogs.removeAt(index);
    await _writeList('myDogs', dogs.map((item) => item.toJson()).toList());
    if (!removed.photo.startsWith('assets/') &&
        !removed.photo.startsWith('picked:')) {
      try {
        final photo = File(removed.photo);
        if (await photo.exists()) await photo.delete();
      } catch (_) {
        // The profile is already removed; an unavailable image file is harmless.
      }
    }
  }

  @override
  Future<void> swipe(String dogId, {required bool liked}) async {
    final seen = _readList('seenDogs').map((e) => e.toString()).toSet()
      ..add(dogId);
    await _writeList('seenDogs', seen.toList());
    if (liked) {
      final likedSet = _readList('likedDogs').map((e) => e.toString()).toSet()
        ..add(dogId);
      await _writeList('likedDogs', likedSet.toList());
    }
  }

  @override
  Future<void> sendRequest(Dog dog) async {
    final sent = _readList('sentRequests')
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (sent.any((request) => request['dogId'] == dog.id)) return;
    sent.insert(0, {
      'dogId': dog.id,
      'name': dog.name,
      'status': 'pending',
      'direction': 'sent',
      'time': 'Ahora',
    });
    await _writeList('sentRequests', sent);
  }

  @override
  Future<List<String>> likedDogs() async =>
      _readList('likedDogs').map((e) => e.toString()).toList();

  @override
  Future<List<Map<String, dynamic>>> matches() async {
    await Future<void>.delayed(_delay);
    final raw = await rootBundle.loadString('assets/json/matches.json');
    final result = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
    final custom = _readList('customMatches')
        .map((e) => Map<String, dynamic>.from(e as Map));
    return [...custom, ...result];
  }

  @override
  Future<List<Map<String, dynamic>>> requests() async {
    await Future<void>.delayed(_delay);
    final raw = await rootBundle.loadString('assets/json/requests.json');
    final result = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
    final statuses = jsonDecode(
      _preferences.getString('requestStatuses') ?? '{}',
    ) as Map<String, dynamic>;
    for (final request in result) {
      if (statuses.containsKey(request['dogId'])) {
        request['status'] = statuses[request['dogId']];
      }
    }
    result.addAll(
      _readList('sentRequests').map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return result;
  }

  @override
  Future<void> answerRequest(String dogId, {required bool accept}) async {
    final statuses = jsonDecode(
      _preferences.getString('requestStatuses') ?? '{}',
    ) as Map<String, dynamic>;
    statuses[dogId] = accept ? 'accepted' : 'declined';
    await _preferences.setString('requestStatuses', jsonEncode(statuses));
    if (accept) {
      final dog = await dogById(dogId);
      if (dog != null) {
        final custom = _readList('customMatches')
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (!custom.any((match) => match['dogId'] == dogId)) {
          custom.insert(0, {
            'dogId': dog.id,
            'name': dog.name,
            'lastMessage': '¡Se aceptó tu solicitud! 🐾',
            'time': 'Ahora',
            'unread': 0,
          });
          await _writeList('customMatches', custom);
        }
      }
    }
  }

  @override
  Future<List<ChatMessage>> messages(String dogId) async {
    await Future<void>.delayed(_delay);
    final stored = _preferences.getString('messages_$dogId');
    if (stored != null) {
      return (jsonDecode(stored) as List)
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final rawConversations = jsonDecode(
      await rootBundle.loadString('assets/json/conversations.json'),
    ) as Map<String, dynamic>;
    final seeded = (rawConversations[dogId] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    await _writeMessages(dogId, seeded);
    return seeded;
  }

  Future<void> _writeMessages(String dogId, List<ChatMessage> messages) =>
      _preferences.setString(
        'messages_$dogId',
        jsonEncode(messages.map((e) => e.toJson()).toList()),
      );

  @override
  Future<void> sendMessage(String dogId, ChatMessage message) async {
    final messages = await this.messages(dogId);
    messages.add(message);
    await _writeMessages(dogId, messages);
  }

  @override
  Future<void> clearConversation(String dogId) =>
      _preferences.setString('messages_$dogId', '[]');
}
