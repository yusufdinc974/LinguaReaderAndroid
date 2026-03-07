import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../main_screen.dart';
import '../onboarding/profile_onboarding_screen.dart';
import '../../services/database_service.dart';

class PhoneVerifyScreen extends StatefulWidget {
  final String phoneNumber;

  const PhoneVerifyScreen({super.key, required this.phoneNumber});

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  final _authService = AuthService();
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.verifyOTP(widget.phoneNumber, _otp);
      if (mounted) {
        final profileComplete = await DatabaseService().isUserProfileComplete();
        if (mounted) {
          if (!profileComplete) {
            await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                  builder: (_) => const ProfileOnboardingScreen.force()),
            );
          }
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainScreen()),
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Verification failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Phone')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              const FoxSpriteAnimator(
                animation: FoxAnimation.idleSouth,
                size: 84,
              ),
              const SizedBox(height: 24),
              Text(
                'Code sent to\n${widget.phoneNumber}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the 6-digit code below',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),

              // OTP boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 44,
                    height: 56,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _controllers[i].text.isNotEmpty
                            ? AppColors.primary
                            : AppColors.border,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      color: AppColors.surface,
                    ),
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      onChanged: (val) {
                        setState(() {});
                        if (val.isNotEmpty && i < 5) {
                          _focusNodes[i + 1].requestFocus();
                        } else if (val.isEmpty && i > 0) {
                          _focusNodes[i - 1].requestFocus();
                        }
                        if (i == 5 && val.isNotEmpty) _verify();
                      },
                    ),
                  );
                }),
              ),

              const SizedBox(height: 40),
              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _verify,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Verify',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  try {
                    await _authService.sendOTP(widget.phoneNumber);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code resent!')),
                      );
                    }
                  } catch (_) {}
                },
                child: const Text('Resend Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
