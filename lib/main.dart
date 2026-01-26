import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/main_screen.dart';
import 'core/theme/app_theme.dart';
import 'services/database_service.dart';

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
    await _databaseService.saveSetting('theme', mode == ThemeMode.light ? 'light' : 'dark');
  }
}

void main() {
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
      home: const MainScreen(),
    );
  }
}
