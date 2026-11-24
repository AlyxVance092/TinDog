import 'package:flutter/material.dart';

class Dog {
  const Dog({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    this.sourceDogId,
    this.intention = 'playdate',
    this.birthDate,
    required this.sex,
    required this.location,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.compatibility,
    required this.vaccines,
    this.vaccineAppliedOn = const {},
    this.vaccineLabelPhotos = const {},
    this.vaccineProducts = const {},
    this.vaccineLots = const {},
    required this.photo,
    required this.about,
    required this.color,
  });

  final String id;
  final String name;
  final String breed;
  final int age;

  /// The owner's dog used to fetch this candidate from Supabase.
  final String? sourceDogId;
  final String intention;
  final DateTime? birthDate;
  final String sex;
  final String location;
  final double? latitude;
  final double? longitude;
  final int? distanceKm;
  final int? compatibility;
  final Map<String, String> vaccines;
  final Map<String, String> vaccineAppliedOn;
  final Map<String, String> vaccineLabelPhotos;
  final Map<String, String> vaccineProducts;
  final Map<String, String> vaccineLots;
  final String photo;
  final String about;
  final String color;

  Color get dominantColor {
    final value = color.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }

  Dog withHealthData({
    required Map<String, String> vaccines,
    Map<String, String> vaccineAppliedOn = const {},
    Map<String, String> vaccineProducts = const {},
    Map<String, String> vaccineLots = const {},
  }) => Dog(
    id: id,
    name: name,
    breed: breed,
    age: age,
    sourceDogId: sourceDogId,
    intention: intention,
    birthDate: birthDate,
    sex: sex,
    location: location,
    latitude: latitude,
    longitude: longitude,
    distanceKm: distanceKm,
    compatibility: compatibility,
    vaccines: vaccines,
    vaccineAppliedOn: vaccineAppliedOn,
    vaccineLabelPhotos: vaccineLabelPhotos,
    vaccineProducts: vaccineProducts,
    vaccineLots: vaccineLots,
    photo: photo,
    about: about,
    color: color,
  );

  factory Dog.fromJson(Map<String, dynamic> json) => Dog(
    id: json['id'] as String,
    name: json['name'] as String,
    breed: json['breed'] as String,
    age: json['age'] as int,
    sourceDogId: json['sourceDogId'] as String?,
    intention: json['intention'] as String? ?? 'playdate',
    birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
    sex: json['sex'] as String,
    location: json['location'] as String,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    distanceKm: json['distanceKm'] as int?,
    compatibility: json['compatibility'] as int?,
    vaccines: Map<String, String>.from(
      (json['vaccines'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    ),
    vaccineAppliedOn: Map<String, String>.from(
      (json['vaccineAppliedOn'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    ),
    vaccineLabelPhotos: Map<String, String>.from(
      (json['vaccineLabelPhotos'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    ),
    vaccineProducts: Map<String, String>.from(
      (json['vaccineProducts'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    ),
    vaccineLots: Map<String, String>.from(
      (json['vaccineLots'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    ),
    photo: json['photo'] as String,
    about: json['about'] as String? ?? '',
    color: json['color'] as String? ?? '#FFDCCB',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'breed': breed,
    'age': age,
    'sourceDogId': sourceDogId,
    'intention': intention,
    'birthDate': birthDate?.toIso8601String(),
    'sex': sex,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'distanceKm': distanceKm,
    'compatibility': compatibility,
    'vaccines': vaccines,
    'vaccineAppliedOn': vaccineAppliedOn,
    'vaccineLabelPhotos': vaccineLabelPhotos,
    'vaccineProducts': vaccineProducts,
    'vaccineLots': vaccineLots,
    'photo': photo,
    'about': about,
    'color': color,
  };
}

class ChatUpdate {
  const ChatUpdate({required this.messages, this.otherUserTyping = false});

  final List<ChatMessage> messages;
  final bool otherUserTyping;
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.mine,
    required this.time,
    this.read = false,
  });

  final String text;
  final bool mine;
  final String time;
  final bool read;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'] as String,
    mine: json['mine'] as bool,
    time: json['time'] as String? ?? '',
    read: json['read'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'mine': mine,
    'time': time,
    'read': read,
  };
}
