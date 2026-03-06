import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/pixel_card.dart';
import '../main_screen.dart';
import 'phone_verify_screen.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _authService = AuthService();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _showPhoneInput = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final response = await _authService.signInWithGoogle();
      if (mounted) {
        if (response == null) {
          // User cancelled
          setState(() => _isLoading = false);
        } else {
          // Success, navigate to app
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Google sign-in failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please enter phone with country code (e.g. +905321234567)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.sendOTP(phone);
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PhoneVerifyScreen(phoneNumber: phone),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to send OTP: $e'),
              backgroundColor: Colors.red),
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
                        const SizedBox(height: 16),

                        // Phone Sign-In Toggle
                        if (!_showPhoneInput)
                          _SocialButton(
                            icon: Icons.phone,
                            label: 'Continue with Phone',
                            onTap: () => setState(() => _showPhoneInput = true),
                          )
                        else ...[
                          PixelCard(
                            child: TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                hintText: '+905321234567',
                                prefixIcon: Icon(Icons.phone),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _sendOTP,
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text('Send Code',
                                  style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ],
                      ],
                    ),

              const SizedBox(height: 40),
              // Divider
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              // Skip / Continue as guest
              TextButton(
                onPressed: () {
                  // Pop the auth screen — main.dart will show MainScreen for guests
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Continue without account',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),

              const SizedBox(height: 32),
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
