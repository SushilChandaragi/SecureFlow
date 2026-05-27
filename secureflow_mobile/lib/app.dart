// SecureFlow Mobile — Root App Widget
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/vault_provider.dart';
import 'utils/logger.dart';

class SecureFlowApp extends StatelessWidget {
  const SecureFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureFlow',
      debugShowCheckedModeBanner: false,
      theme: buildSFTheme(),
      home: const _AppShell(),
    );
  }
}

/// AppShell drives the top-level navigation state:
/// Splash → Login → Dashboard (and back to Login on vault lock)
class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

enum _AppState { splash, login, dashboard }

class _AppShellState extends ConsumerState<_AppShell>
    with WidgetsBindingObserver {
  _AppState _state = _AppState.splash;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lock vault when app goes to background (§5 Secure Behaviors)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    sfLog('AppShell: lifecycle=$state');
    if (state == AppLifecycleState.paused) {
      if (_state == _AppState.dashboard) {
        sfLog('AppShell: background -> lock + login');
        ref.read(sessionProvider.notifier).lock();
        setState(() => _state = _AppState.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to session lock events from outside
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if ((prev?.isUnlocked ?? false) && !next.isUnlocked) {
        if (mounted && _state == _AppState.dashboard) {
          sfLog('AppShell: session locked -> login');
          setState(() => _state = _AppState.login);
        }
      }
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: _buildScreen(),
    );
  }

  Widget _buildScreen() {
    switch (_state) {
      case _AppState.splash:
        return SplashScreen(
          key: const ValueKey('splash'),
          onComplete: () {
            sfLog('AppShell: splash complete -> login');
            setState(() => _state = _AppState.login);
          },
        );
      case _AppState.login:
        return LoginScreen(
          key: const ValueKey('login'),
          onUnlocked: () {
            sfLog('AppShell: login unlocked -> dashboard');
            setState(() => _state = _AppState.dashboard);
          },
        );
      case _AppState.dashboard:
        return const DashboardScreen(key: ValueKey('dashboard'));
    }
  }
}
