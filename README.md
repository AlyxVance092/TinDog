# TinDog

App Flutter para explorar perros con perfiles de salud y pedigrí, enviar solicitudes de cruza y chatear después de un match. Esta entrega usa datos y persistencia locales; no necesita un servidor.

## Requisitos

- Flutter estable y Dart incluidos con Flutter.
- Android Studio con Android SDK para compilar Android.
- Un emulador Android o dispositivo conectado para `flutter run`.

## Ejecutar

```bash
flutter pub get
flutter run
```

Credenciales para recorrer la demo:

- Correo: `demo@tindog.mx`
- Contraseña: `Demo1234`

También puedes crear una cuenta local desde Registro. Las cuentas, perros registrados, deslizados, solicitudes respondidas y mensajes se guardan en el almacenamiento del dispositivo.

## Generar APK

APK de depuración para probar:

```bash
flutter build apk --debug
```

APK de release firmado con la clave de depuración del proyecto (para pruebas, no para publicar):

```bash
flutter build apk
```

El archivo queda en `build/app/outputs/flutter-apk/app-release.apk`. Para publicar en Play Store, configura una clave de firma propia siguiendo la guía de Flutter.

## Datos y arquitectura

- `assets/json/dogs.json`: perfiles de ejemplo y vacunas.
- `assets/json/matches.json`: matches de ejemplo.
- `assets/json/requests.json`: solicitudes de ejemplo.
- `assets/json/conversations.json`: conversaciones de ejemplo.
- `assets/dogs/`: 12 fotos de perros incluidas en el paquete; no se descargan al ejecutar la app. Sus fuentes están en `assets/dogs/SOURCES.md`.
- `assets/fonts/`: Plus Jakarta Sans y Bricolage Grotesque, empaquetadas con sus licencias OFL.
- `lib/data/repository.dart`: contrato `TinDogRepository` e implementación local `LocalTinDogRepository`. Las pantallas usan el contrato, de modo que el backend futuro puede añadir otro adaptador sin cambiar los widgets.
- `shared_preferences`: sesión, preferencias del demo, solicitudes, likes y mensajes.
- `path_provider` e `image_picker`: copia y persistencia local de fotos seleccionadas para perros registrados.
- `sensors_plus` y `battery_plus`: inclinación por giroscopio y modo de bajo consumo.

## Pantallas

Bienvenida, Login, Registro, Registrar mi perro por pasos, Descubrir, Filtros, Detalle, Matches y Solicitudes, Chat y Perfil. La app incluye tema claro/oscuro, animaciones, efectos de deslizamiento, transición Hero y vibración. Si Android tiene desactivadas las animaciones, se usan transiciones simples y se omiten los efectos con partículas.
