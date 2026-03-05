import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/main_screen.dart';
import 'features/auth/auth_screen.dart';
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

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://hvhbdouycrskhxayubwj.supabase.co',
    anonKey: 'sb_publishable_wxmdlln4RQTnmCUfIU2V_w_HGoExea7',
  );

  // Initialize RevenueCat
  await SubscriptionService.initialize();

  // If a user is already logged in, sync their ID to RevenueCat
  final existingUser = Supabase.instance.client.auth.currentUser;
  if (existingUser != null) {
    await SubscriptionService.loginUser(existingUser.id);
    await SyncService.syncOnLogin();
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
  bool _shownAuthOnce = false;

  @override
  void initState() {
    super.initState();
    // Show the auth screen on first launch if not logged in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null && !_shownAuthOnce) {
        _shownAuthOnce = true;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for login events to sync RevenueCat user
    ref.listen(authStateProvider, (_, next) {
      next.whenData((state) async {
        if (state.event == AuthChangeEvent.signedIn &&
            state.session?.user != null) {
          await SubscriptionService.loginUser(state.session!.user.id);
          await SyncService.syncOnLogin();
        } else if (state.event == AuthChangeEvent.signedOut) {
          await SubscriptionService.logoutUser();
        }
      });
    });

    return const MainScreen();
  }
}
