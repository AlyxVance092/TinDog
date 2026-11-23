# TinDog

Aplicacion Flutter para perfiles de perros, descubrimiento, solicitudes y chat.

## Supabase conectado

La app usa el proyecto configurado en `lib/main.dart` y las tablas existentes: `dogs`, `breeds`, `dog_photos`, `dog_pedigrees`, `dog_health_status`, `swipes`, `breeding_requests`, `matches`, `conversations`, `messages` y `users`.

El registro de intereses llama a `public.swipe`. Esa funcion decide si el resultado es un like de convivencia, una solicitud de cruza o un match. Para responder una solicitud se llama a `public.respond_breeding_request`.

No ejecutes `supabase/schema.sql` en este proyecto: es solo un esquema de ejemplo para una base nueva y vacia.

## Fotos y cartilla de salud

Los perfiles usan el bucket privado `dog-photos`. La app guarda la ruta del objeto y solicita una URL firmada para mostrar cada foto; no guarda URLs publicas ni enlaces temporales en la base.

La cartilla usa los tipos de vacuna de `health_item_types` y guarda fecha de aplicacion, vencimiento y foto de etiqueta en `dog_health_records`. Los registros nuevos quedan pendientes de revision.

El chat guarda mensajes en `messages` y escucha cambios de Realtime. La base debe tener Realtime habilitado para esa tabla para recibir mensajes nuevos al instante.

## Ejecutar

```bash
flutter pub get
flutter run
```

## Arquitectura

- `lib/data/repository.dart`: contrato de datos y adaptador local para desarrollo.
- `lib/data/supabase_repository.dart`: adaptador a las tablas y funciones del proyecto Supabase.
- `lib/main.dart`: inicializa Supabase y conecta el adaptador remoto.
- `supabase/schema.sql`: esquema opcional para una instalacion nueva; no aplicar a la base existente.
- `assets/json/`: datos de muestra usados por el adaptador local.
