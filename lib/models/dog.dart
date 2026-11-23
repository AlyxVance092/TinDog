import 'package:flutter/material.dart';

class Dog {
  const Dog({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    this.intention = 'playdate',
    this.birthDate,
    required this.sex,
    required this.location,
    this.distanceKm,
    this.compatibility,
    required this.pedigree,
    this.hasPedigree = false,
    required this.pedigreeNumber,
    required this.vaccines,
    this.vaccineAppliedOn = const {},
    this.vaccineLabelPhotos = const {},
    required this.photo,
    required this.about,
    required this.color,
  });

  final String id;
  final String name;
  final String breed;
  final int age;
  final String intention;
  final DateTime? birthDate;
  final String sex;
  final String location;
  final int? distanceKm;
  final int? compatibility;
  final bool pedigree;
  final bool hasPedigree;
  final String pedigreeNumber;
  final Map<String, String> vaccines;
  final Map<String, String> vaccineAppliedOn;
  final Map<String, String> vaccineLabelPhotos;
  final String photo;
  final String about;
  final String color;

  Color get dominantColor {
    final value = color.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }

  factory Dog.fromJson(Map<String, dynamic> json) => Dog(
    id: json['id'] as String,
    name: json['name'] as String,
    breed: json['breed'] as String,
    age: json['age'] as int,
    intention: json['intention'] as String? ?? 'playdate',
    birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
    sex: json['sex'] as String,
    location: json['location'] as String,
    distanceKm: json['distanceKm'] as int?,
    compatibility: json['compatibility'] as int?,
    pedigree: json['pedigree'] as bool? ?? false,
    hasPedigree:
        json['hasPedigree'] as bool? ?? (json['pedigree'] as bool? ?? false),
    pedigreeNumber: json['pedigreeNumber'] as String? ?? '',
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
    photo: json['photo'] as String,
    about: json['about'] as String? ?? '',
    color: json['color'] as String? ?? '#FFDCCB',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'breed': breed,
    'age': age,
    'intention': intention,
    'birthDate': birthDate?.toIso8601String(),
    'sex': sex,
    'location': location,
    'distanceKm': distanceKm,
    'compatibility': compatibility,
    'pedigree': pedigree,
    'hasPedigree': hasPedigree,
    'pedigreeNumber': pedigreeNumber,
    'vaccines': vaccines,
    'vaccineAppliedOn': vaccineAppliedOn,
    'vaccineLabelPhotos': vaccineLabelPhotos,
    'photo': photo,
    'about': about,
    'color': color,
  };
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
