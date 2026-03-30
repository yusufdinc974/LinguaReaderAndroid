import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../main_screen.dart';
import '../onboarding/profile_onboarding_screen.dart';
import '../../services/database_service.dart';
import '../../services/sync_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _authService = AuthService();
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final response = await _authService.signInWithGoogle();
      if (mounted) {
        if (response == null) {
          // User cancelled
          setState(() => _isLoading = false);
        } else {
          // Success! The _AuthGate in main.dart will notice the new session
          // and automatically show the Onboarding or Home screen.
          // We just need to stop the loading spinner.
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);

        String errorMessage = e.toString();
        if (errorMessage.contains('10:')) {
          errorMessage =
              'Configuration Error (10): Please ensure your SHA-1 fingerprint and Web Client ID are correctly registered in the Google Cloud Console.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: $errorMessage'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              const FoxMascotHeader(
                title: 'LinguaReader',
                subtitle: 'Your fox guide for daily language reading.',
                animation: FoxAnimation.walkEast,
              ),
              const SizedBox(height: 24),
              Text(
                'LinguaReader',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: AppColors.primaryLight,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to sync your vocabulary\nacross all your devices',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 48),

              // Google Sign-In
              _isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        _SocialButton(
                          icon: Icons.g_mobiledata,
                          label: 'Continue with Google',
                          onTap: _signInWithGoogle,
                        ),
                      ],
                    ),

              const SizedBox(height: 40),
              Text(
                'By signing in, you agree to our Terms of Service\nand Privacy Policy.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.6),
                    fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}
