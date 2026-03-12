import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/main_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/onboarding/profile_onboarding_screen.dart';
import 'core/theme/app_theme.dart';
import 'services/database_service.dart';
import 'services/subscription_service.dart';
import 'services/sync_service.dart';
import 'providers/auth_provider.dart';

// Theme provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  final _databaseService = DatabaseService();

  Future<void> _loadTheme() async {
    final theme = await _databaseService.getSetting('theme');
    if (theme == 'light') {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark;
    }
  }

  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
      await _databaseService.saveSetting('theme', 'light');
    } else {
      state = ThemeMode.dark;
      await _databaseService.saveSetting('theme', 'dark');
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    await _databaseService.saveSetting(
        'theme', mode == ThemeMode.light ? 'light' : 'dark');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://hvhbdouycrskhxayubwj.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2aGJkb3V5Y3Jza2h4YXl1YndqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2OTk0NzksImV4cCI6MjA4ODI3NTQ3OX0.89TXY7GE4yzBk-2Jp_nP-BQv0fVlmVcjDBtHTWOgzew',
  );

  // Initialize RevenueCat
  await SubscriptionService.initialize();

  // If a user is already logged in, sync their ID to RevenueCat
  final existingUser = Supabase.instance.client.auth.currentUser;
  if (existingUser != null) {
    SubscriptionService.loginUser(existingUser.id); // Don't strictly await here to prevent splash hang
  }

  runApp(const ProviderScope(child: LinguaReaderApp()));
}

class LinguaReaderApp extends ConsumerWidget {
  const LinguaReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'LinguaReader',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: const _AuthGate(),
    );
  }
}

/// Listens to Supabase auth state and decides which screen to show.
/// If logged in → MainScreen. If not → AuthScreen (on first launch).
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool _profileComplete = false;
  bool _isCheckingProfile = true;

  @override
  void initState() {
    super.initState();
    // Initial check if we have a user
    _checkProfileStatus();
  }

  Future<void> _checkProfileStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isCheckingProfile = false;
          _profileComplete = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isCheckingProfile = true);

    try {
      // 1. Sync data if we're signed in on startup
      await SyncService.syncOnLogin();
      
      // 2. Check profile completeness
      final complete = await DatabaseService().isUserProfileComplete();
      
      if (mounted) {
        setState(() {
          _profileComplete = complete;
          _isCheckingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('Error in AuthGate profile check: $e');
      if (mounted) setState(() => _isCheckingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes to re-check profile
    ref.listen(authStateProvider, (previous, next) {
      next.whenData((state) {
        if (state.event == AuthChangeEvent.signedIn || 
            state.event == AuthChangeEvent.signedOut) {
          _checkProfileStatus();
        }
      });
    });

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (state) {
        final user = state.session?.user;

        if (user == null) {
          return const AuthScreen();
        }

        if (_isCheckingProfile) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Syncing your Lexi profile...', 
                    style: TextStyle(color: Colors.grey, fontFamily: 'monospace')),
                ],
              ),
            ),
          );
        }

        if (!_profileComplete) {
          // If profile is not complete, show onboarding
          return ProfileOnboardingScreen.force(
            key: const ValueKey('onboarding'),
            onComplete: _checkProfileStatus,
          );
        }

        return const MainScreen();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Auth Error: $error')),
      ),
    );
  }
}
