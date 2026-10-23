import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repository.dart';
import 'screens/auth_screens.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(TinDogApp(repository: LocalTinDogRepository(preferences)));
}

class TinDogApp extends StatefulWidget {
  const TinDogApp({super.key, required this.repository});
  final TinDogRepository repository;

  @override
  State<TinDogApp> createState() => _TinDogAppState();
}

class _TinDogAppState extends State<TinDogApp> with WidgetsBindingObserver {
  bool _dark = false;
  Timer? _batteryPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryMode();
    _batteryPoll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshBatteryMode(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshBatteryMode();
  }

  Future<void> _refreshBatteryMode() async {
    try {
      final enabled = await Battery().isInBatterySaveMode;
      if (mounted && batterySaverMode != enabled) {
        setState(() => batterySaverMode = enabled);
      }
    } catch (_) {
      // Not all platforms expose a battery saver setting.
    }
  }

  @override
  void dispose() {
    _batteryPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _toggleTheme() => setState(() => _dark = !_dark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TinDog',
      debugShowCheckedModeBanner: false,
      theme: tinTheme(dark: _dark),
      home: EntryGate(
        repository: widget.repository,
        dark: _dark,
        onTheme: _toggleTheme,
      ),
    );
  }
}

class EntryGate extends StatelessWidget {
  const EntryGate({
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
    return FutureBuilder<String?>(
      future: repository.restoreSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupScreen();
        }
        final email = snapshot.data;
        if (email != null) {
          return HomeShell(
            repository: repository,
            email: email,
            dark: dark,
            onTheme: onTheme,
          );
        }
        return WelcomeScreen(
          repository: repository,
          dark: dark,
          onTheme: onTheme,
        );
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          color: TinColors.coral,
          strokeWidth: 2.5,
        ),
      ),
    ),
  );
}
