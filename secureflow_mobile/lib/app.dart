// SecureFlow Mobile — Root App Widget
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/colors.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/vault_provider.dart';
import 'utils/logger.dart';

// Grace period before vault locks on background (default 60 s; max 120 s)
const _kLockGraceSeconds = 60;

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

  // ── Background blur + grace-period lock ──────────────────────────────────
  bool   _isObscured = false;   // true = app is in background → show blur
  Timer? _lockTimer;             // fires after _kLockGraceSeconds to lock vault

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    sfLog('AppShell: lifecycle=$state');

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Immediately apply blur overlay to hide sensitive content in recents
      if (_state == _AppState.dashboard) {
        sfLog('AppShell: background → blur + start ${_kLockGraceSeconds}s grace timer');
        if (mounted) setState(() => _isObscured = true);
        // Cancel any previous timer and start a fresh countdown
        _lockTimer?.cancel();
        _lockTimer = Timer(const Duration(seconds: _kLockGraceSeconds), () {
          sfLog('AppShell: grace period expired → lock vault');
          ref.read(sessionProvider.notifier).lock();
          if (mounted) {
            setState(() {
              _isObscured = false;
              _state = _AppState.login;
            });
          }
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isObscured) {
        sfLog('AppShell: resumed within grace period → cancel lock timer');
        _lockTimer?.cancel();
        _lockTimer = null;
        if (mounted) setState(() => _isObscured = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to session lock events (e.g. manual lock from settings)
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if ((prev?.isUnlocked ?? false) && !next.isUnlocked) {
        if (mounted && _state == _AppState.dashboard) {
          sfLog('AppShell: session locked → login');
          _lockTimer?.cancel();
          setState(() {
            _isObscured = false;
            _state = _AppState.login;
          });
        }
      }
    });

    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: _buildScreen(),
        ),
        // Gaussian blur overlay — applied immediately on background
        if (_isObscured)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  color: SFColors.bgPrimary.withAlpha(180),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, color: SFColors.textFaint, size: 36),
                        SizedBox(height: 12),
                        Text(
                          'VAULT OBSCURED',
                          style: TextStyle(
                            color: SFColors.textFaint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScreen() {
    switch (_state) {
      case _AppState.splash:
        return SplashScreen(
          key: const ValueKey('splash'),
          onComplete: () {
            sfLog('AppShell: splash complete → login');
            setState(() => _state = _AppState.login);
          },
        );
      case _AppState.login:
        return LoginScreen(
          key: const ValueKey('login'),
          onUnlocked: () {
            sfLog('AppShell: login unlocked → dashboard');
            setState(() => _state = _AppState.dashboard);
          },
        );
      case _AppState.dashboard:
        return const DashboardScreen(key: ValueKey('dashboard'));
    }
  }
}
