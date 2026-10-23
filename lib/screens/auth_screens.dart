import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../data/repository.dart';
import '../models/dog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _passwordPattern = RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$');

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.repository,
    required this.dark,
    required this.onTheme,
  });
  final TinDogRepository repository;
  final bool dark;
  final VoidCallback onTheme;
  @override
  Widget build(BuildContext context) {
    final dog = Dog.fromJson({
      'id': 'hero',
      'name': 'Bruno',
      'breed': 'Golden Retriever',
      'age': 3,
      'sex': 'Macho',
      'location': 'CDMX',
      'distanceKm': 1,
      'compatibility': 98,
      'pedigree': true,
      'pedigreeNumber': '',
      'vaccines': {},
      'photo': 'assets/dogs/dog_01.svg',
      'about': '',
      'color': '#F4D9B6',
    });
    return AppPage(
      child: Stack(
        children: [
          const Positioned.fill(child: _WelcomeAtmosphere()),
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(25, 18, 25, 28),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        const BrandMark(),
                        const Spacer(),
                        IconButton(
                          onPressed: onTheme,
                          icon: Icon(
                            dark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            color: TinColors.coral,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ParallaxHeroCard(dog: dog),
                    const SizedBox(height: 24),
                    Text(
                      'Su próxima gran\namistad empieza aquí.',
                      style: TextStyle(
                        fontFamily: 'Bricolage Grotesque',
                        fontWeight: FontWeight.w900,
                        fontSize: 33,
                        height: 1.08,
                        letterSpacing: -1.1,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Conecta con familias que comparten tu amor por los perros y la crianza responsable.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 23),
                    PrimaryButton(
                      label: 'Crear cuenta',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () => _open(
                        context,
                        const _AuthMode.register(),
                        repository,
                        dark,
                        onTheme,
                      ),
                    ),
                    const SizedBox(height: 11),
                    PressScale(
                      onTap: () => _open(
                        context,
                        const _AuthMode.login(),
                        repository,
                        dark,
                        onTheme,
                      ),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: TinColors.coral.withValues(alpha: .38),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'Ya tengo una cuenta',
                            style: TextStyle(
                              color: TinColors.coral,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Center(
                      child: Text(
                        'Perfiles verificados · Vacunas al día · Comunidad segura',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _open(
  BuildContext context,
  _AuthMode mode,
  TinDogRepository repository,
  bool dark,
  VoidCallback onTheme,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AuthScreen(
        repository: repository,
        dark: dark,
        onTheme: onTheme,
        register: mode.register,
      ),
    ),
  );
}

class _AuthMode {
  const _AuthMode._(this.register);
  const _AuthMode.login() : this._(false);
  const _AuthMode.register() : this._(true);
  final bool register;
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.repository,
    required this.dark,
    required this.onTheme,
    required this.register,
  });
  final TinDogRepository repository;
  final bool dark;
  final VoidCallback onTheme;
  final bool register;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  String? _serverError;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _serverError = null;
    });
    final success = widget.register
        ? await widget.repository.register(
            _name.text,
            _email.text,
            _password.text,
          )
        : await widget.repository.login(_email.text, _password.text);
    if (!mounted) return;
    if (!success) {
      setState(() {
        _loading = false;
        _serverError = widget.register
            ? 'Ya existe una cuenta con este correo.'
            : 'Correo o contraseña incorrectos.';
      });
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeShell(
          repository: widget.repository,
          email: _email.text.trim().toLowerCase(),
          dark: widget.dark,
          onTheme: widget.onTheme,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      const BrandMark(small: true),
                      const Spacer(),
                      const SizedBox(width: 44),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    widget.register ? 'Únete a la manada' : 'Qué gusto verte',
                    style: TextStyle(
                      fontFamily: 'Bricolage Grotesque',
                      fontWeight: FontWeight.w900,
                      fontSize: 31,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.register
                        ? 'Crea tu perfil y empecemos a encontrar grandes conexiones.'
                        : 'Entra a tu cuenta para seguir buscando su match ideal.',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!widget.register) ...[
                    GlassCard(
                      padding: const EdgeInsets.all(13),
                      radius: 18,
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: TinColors.peach,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.lightbulb_outline_rounded,
                              color: TinColors.coral,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Demo: demo@tindog.mx · Demo1234',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          PressScale(
                            onTap: () {
                              setState(() {
                                _email.text = 'demo@tindog.mx';
                                _password.text = 'Demo1234';
                              });
                            },
                            child: const Text(
                              'Usar',
                              style: TextStyle(
                                color: TinColors.coral,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Form(
                    key: _form,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      children: [
                        if (widget.register) ...[
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Tu nombre',
                              hintText: '¿Cómo te llamas?',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (v) => (v ?? '').trim().length < 2
                                ? 'Escribe tu nombre'
                                : null,
                          ),
                          const SizedBox(height: 13),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                            hintText: 'tu@correo.com',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (v) =>
                              _emailPattern.hasMatch((v ?? '').trim())
                              ? null
                              : 'Ingresa un correo válido',
                        ),
                        const SizedBox(height: 13),
                        TextFormField(
                          controller: _password,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            hintText: '8 caracteres, una mayúscula y un número',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                          validator: (v) => _passwordPattern.hasMatch(v ?? '')
                              ? null
                              : 'Usa 8+ caracteres, una mayúscula y un número',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.register)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: TinColors.green.withValues(alpha: .85),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Mínimo 8 caracteres, una mayúscula y un número.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_serverError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _serverError!,
                        style: const TextStyle(
                          color: TinColors.coral,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: widget.register ? 'Crear cuenta' : 'Iniciar sesión',
                    icon: widget.register
                        ? Icons.pets_rounded
                        : Icons.arrow_forward_rounded,
                    loading: _loading,
                    onPressed: _loading ? null : _submit,
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          widget.register
                              ? '¿Ya tienes cuenta? '
                              : '¿Primera vez en TinDog? ',
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 13,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            Navigator.pop(context);
                          }),
                          child: Text(
                            widget.register ? 'Inicia sesión' : 'Regístrate',
                            style: const TextStyle(
                              color: TinColors.coral,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Tus datos se guardan de forma local en este dispositivo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? Colors.white38
                            : TinColors.ink.withValues(alpha: .46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParallaxHeroCard extends StatefulWidget {
  const _ParallaxHeroCard({required this.dog});
  final Dog dog;

  @override
  State<_ParallaxHeroCard> createState() => _ParallaxHeroCardState();
}

class _ParallaxHeroCardState extends State<_ParallaxHeroCard>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AccelerometerEvent>? _sensor;
  late final AnimationController _float;
  Offset _motion = Offset.zero;
  Offset? _gravityAtRest;
  DateTime _lastSensorUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
      value: .5,
    );
    if (!motionReduced) {
      _float.repeat(reverse: true);
      try {
        _sensor =
            accelerometerEventStream(
              samplingPeriod: SensorInterval.normalInterval,
            ).listen((event) {
              if (!mounted || _dragging || motionReduced) return;
              final gravity = _gravityAtRest ??= Offset(event.x, event.y);
              final now = DateTime.now();
              if (now.difference(_lastSensorUpdate).inMilliseconds < 32) return;
              _lastSensorUpdate = now;
              setState(() {
                _motion = Offset(
                  ((event.x - gravity.dx) / 9.81).clamp(-1, 1).toDouble(),
                  ((event.y - gravity.dy) / 9.81).clamp(-1, 1).toDouble(),
                );
              });
            }, onError: (_) {});
      } catch (_) {
        // Dragging on the card remains available when a sensor is missing.
      }
    }
  }

  @override
  void dispose() {
    _sensor?.cancel();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (motionReduced && _float.isAnimating) _float.stop();
      if (!motionReduced && !_float.isAnimating) {
        _float.repeat(reverse: true);
      }
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _dragging = true,
        onPointerMove: (event) {
          final width = constraints.maxWidth.clamp(1, double.infinity);
          setState(() {
            _motion = Offset(
              ((event.localPosition.dx / width) * 2 - 1)
                  .clamp(-1, 1)
                  .toDouble(),
              ((event.localPosition.dy / 315) * 2 - 1).clamp(-1, 1).toDouble(),
            );
          });
        },
        onPointerUp: (_) => setState(() {
          _dragging = false;
          _motion = Offset.zero;
        }),
        onPointerCancel: (_) => setState(() {
          _dragging = false;
          _motion = Offset.zero;
        }),
        child: AnimatedBuilder(
          animation: _float,
          builder: (context, _) {
            final motion = motionReduced ? Offset.zero : _motion;
            final bob = motionReduced
                ? 0.0
                : math.sin(_float.value * math.pi) * 5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0014)
                ..rotateX(-motion.dy * .055)
                ..rotateY(motion.dx * .075),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: TinColors.coral.withValues(alpha: .17),
                      blurRadius: 35,
                      offset: Offset(0, 19 + bob),
                    ),
                    BoxShadow(
                      color: TinColors.ink.withValues(alpha: .08),
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  radius: 34,
                  child: SizedBox(
                    height: 315,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(
                              -motion.dx * 18,
                              -motion.dy * 15 + bob,
                            ),
                            child: Transform.scale(
                              scale: 1.11,
                              child: DogPortrait(dog: widget.dog),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0x24FFFFFF),
                                  Colors.transparent,
                                  Color(0x03000000),
                                  Color(0x4D2B1F1A),
                                ],
                                stops: [0, .34, .68, 1],
                              ),
                            ),
                          ),
                        ),
                        if (!motionReduced)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: Alignment(
                                      -.65 + motion.dx * .55,
                                      -.75 + motion.dy * .45,
                                    ),
                                    radius: .95,
                                    colors: [
                                      Colors.white.withValues(alpha: .4),
                                      Colors.white.withValues(alpha: .08),
                                      Colors.transparent,
                                    ],
                                    stops: const [0, .22, .72],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 15 + motion.dx * 5,
                          top: 15 + motion.dy * 5,
                          child: _HeroBadge(
                            icon: Icons.verified_rounded,
                            label: 'Cruza responsable',
                            color: TinColors.green,
                          ),
                        ),
                        Positioned(
                          right: 15 + motion.dx * 9,
                          top: 72 + motion.dy * 8 - bob,
                          child: _HeroBadge(
                            icon: Icons.vaccines_rounded,
                            label: 'Vacunas al día',
                            color: TinColors.coral,
                          ),
                        ),
                        Positioned(
                          right: 26 + motion.dx * 15,
                          top: 145 + motion.dy * 18 + bob,
                          child: Transform.rotate(
                            angle: motion.dx * .16,
                            child: Container(
                              width: 47,
                              height: 47,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .88),
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x302B1F1A),
                                    blurRadius: 16,
                                    offset: Offset(0, 7),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.favorite_rounded,
                                color: TinColors.coral,
                                size: 23,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16 + motion.dx * 4,
                          right: 16 - motion.dx * 4,
                          bottom: 15,
                          child: Transform.translate(
                            offset: Offset(motion.dx * 7, -motion.dy * 7),
                            child: GlassCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              radius: 19,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.favorite_rounded,
                                    color: TinColors.coral,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Encuentra su mejor match',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: TinColors.peach,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      '98%',
                                      style: TextStyle(
                                        color: TinColors.coral,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: .8)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A2B1F1A),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: TinColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _WelcomeAtmosphere extends StatefulWidget {
  const _WelcomeAtmosphere();

  @override
  State<_WelcomeAtmosphere> createState() => _WelcomeAtmosphereState();
}

class _WelcomeAtmosphereState extends State<_WelcomeAtmosphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    );
    if (!motionReduced) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (motionReduced && _controller.isAnimating) _controller.stop();
    if (!motionReduced && !_controller.isAnimating) _controller.repeat();

    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final t = motionReduced ? .16 : _controller.value;
            final base = dark ? TinColors.dark : TinColors.cream;
            final blobs = <_AtmosphereSpec>[
              _AtmosphereSpec(
                color: dark ? const Color(0xFF804A39) : TinColors.peach,
                size: 290,
                x: width * .70 + math.sin(t * math.pi * 2) * 25,
                y: height * .20 + math.cos(t * math.pi * 2) * 24,
              ),
              _AtmosphereSpec(
                color: dark ? const Color(0xFF17654D) : TinColors.green,
                size: 270,
                x: width * .08 + math.sin((t + .34) * math.pi * 2) * 22,
                y: height * .70 + math.cos((t + .34) * math.pi * 2) * 26,
              ),
              _AtmosphereSpec(
                color: dark ? const Color(0xFF8B4938) : TinColors.coral,
                size: 205,
                x: width * .82 + math.sin((t + .68) * math.pi * 2) * 16,
                y: height * .90 + math.cos((t + .68) * math.pi * 2) * 20,
              ),
            ];
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: dark
                            ? [base, const Color(0xFF251C18), base]
                            : [base, const Color(0xFFFFF9F4), base],
                      ),
                    ),
                  ),
                ),
                for (final blob in blobs)
                  Positioned(
                    left: blob.x - blob.size / 2,
                    top: blob.y - blob.size / 2,
                    child: Transform.scale(
                      scale: motionReduced
                          ? 1
                          : 1 + .07 * math.sin(t * math.pi * 2 + blob.size),
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: motionReduced ? 0 : 42,
                          sigmaY: motionReduced ? 0 : 42,
                        ),
                        child: Container(
                          width: blob.size,
                          height: blob.size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                blob.color.withValues(alpha: dark ? .19 : .29),
                                blob.color.withValues(alpha: dark ? .12 : .19),
                                blob.color.withValues(alpha: 0),
                              ],
                              stops: const [0, .48, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!motionReduced)
                  for (var i = 0; i < 7; i++)
                    _buildParticle(i, width, height, t, dark),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildParticle(int index, double width, double height, double t, bool dark) {
    final phase = (t * .35 + index * .173) % 1;
    final x = width * (.11 + ((index * 37) % 79) / 100);
    final y = height * (1.08 - phase * 1.2);
    final icons = [
      Icons.pets_rounded,
      Icons.favorite_rounded,
      Icons.pets_rounded,
      Icons.auto_awesome_rounded,
    ];
    final colors = [TinColors.coral, TinColors.green, TinColors.peach];
    final color = colors[index % colors.length];
    return Positioned(
      left: x,
      top: y,
      child: Transform.rotate(
        angle: math.sin((t + index) * math.pi * 2) * .18,
        child: Icon(
          icons[index % icons.length],
          size: 12 + (index % 3) * 3,
          color: (dark ? Colors.white : color).withValues(alpha: .12),
        ),
      ),
    );
  }
}

class _AtmosphereSpec {
  const _AtmosphereSpec({
    required this.color,
    required this.size,
    required this.x,
    required this.y,
  });

  final Color color;
  final double size;
  final double x;
  final double y;
}
