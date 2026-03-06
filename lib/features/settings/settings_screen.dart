import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../services/subscription_service.dart';
import '../../core/constants/app_colors.dart';
import '../../main.dart';
import '../auth/auth_screen.dart';
import '../subscription/paywall_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _databaseService = DatabaseService();
  final _apiKeyController = TextEditingController();
  bool _isLoading = true;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final apiKey = await _databaseService.getSetting('deepl_api_key');
    final isPremium = await SubscriptionService.isPremium();

    if (mounted) {
      if (apiKey != null) _apiKeyController.text = apiKey;
      setState(() {
        _isPremium = isPremium;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    await _databaseService.saveSetting(
        'deepl_api_key', _apiKeyController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Theme Toggle Section
                const Text(
                  'Appearance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.2),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      color: AppColors.primary,
                    ),
                    title: const Text('Dark Mode'),
                    subtitle: Text(isDarkMode ? 'On' : 'Off'),
                    trailing: Switch(
                      value: isDarkMode,
                      onChanged: (value) {
                        ref.read(themeProvider.notifier).toggleTheme();
                      },
                      activeColor: AppColors.primary,
                    ),
                    onTap: () {
                      ref.read(themeProvider.notifier).toggleTheme();
                    },
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Premium',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage your premium plan and unlock paid features.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.2),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      _isPremium
                          ? Icons.verified
                          : Icons.workspace_premium_outlined,
                      color: _isPremium ? Colors.green : Colors.amber,
                    ),
                    title: Text(
                        _isPremium ? 'Premium Active' : 'Upgrade to Premium'),
                    subtitle: Text(
                      _isPremium
                          ? 'You have access to all premium features.'
                          : 'Unlock Gemini explanations and advanced tools.',
                    ),
                    trailing: ElevatedButton(
                      onPressed: _openPremiumPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isPremium ? Colors.green : AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isPremium ? 'Manage' : 'View Plans'),
                    ),
                    onTap: _openPremiumPage,
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Translation API',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your DeepL API Key to enable high-quality translations. Leave empty to use the free limited service.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Translation language is now selected from the word popup while reading PDFs.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'DeepL API Key (Free or Pro)',
                    border: OutlineInputBorder(),
                    helperText: "Starts with 'f6...' (Free) or similar",
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your API Key is stored locally and used only to communicate directly with DeepL.',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.7),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Save Settings',
                      style: TextStyle(fontSize: 16)),
                ),

                const SizedBox(height: 32),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout, color: AppColors.error),
                    label: const Text('Sign Out',
                        style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await SubscriptionService.logoutUser();
      await AuthService().signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Future<void> _openPremiumPage() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    if (!mounted) return;
    if (result == true) {
      await _loadSettings();
    }
  }
}
