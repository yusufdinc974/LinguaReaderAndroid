import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // --- Google Sign-In ---
  Future<AuthResponse?> signInWithGoogle() async {
    // Note: This ID must match the 'Web client' in your Google Cloud Console
    const webClientId =
        '436499725060-0ldln8g1hp65fqkhg1t2co8g6d6v6io9.apps.googleusercontent.com';

    try {
      final googleSignIn = GoogleSignIn(serverClientId: webClientId);
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) return null; // User cancelled

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) throw Exception('No Access Token from Google');
      if (idToken == null) throw Exception('No ID Token from Google');

      return await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      print('DEBUG: Google Sign-In Error: $e');
      if (e.toString().contains('10:')) {
        print(
            'DEBUG: This is a Developer Error (10). Check your SHA-1 and Web Client ID.');
      }
      rethrow;
    }
  }

  // --- Phone Sign-In (Step 1: Send OTP) ---
  Future<void> sendOTP(String phoneNumber) async {
    await _supabase.auth.signInWithOtp(phone: phoneNumber);
  }

  // --- Phone Sign-In (Step 2: Verify OTP) ---
  Future<AuthResponse> verifyOTP(String phoneNumber, String otp) async {
    return await _supabase.auth.verifyOTP(
      phone: phoneNumber,
      token: otp,
      type: OtpType.sms,
    );
  }

  // --- Sign Out ---
  Future<void> signOut() async {
    // Note: This ID must match the 'Web client' in your Google Cloud Console
    const webClientId =
        '436499725060-0ldln8g1hp65fqkhg1t2co8g6d6v6io9.apps.googleusercontent.com';
    try {
      final googleSignIn = GoogleSignIn(serverClientId: webClientId);
      await googleSignIn.signOut();
    } catch (_) {
      // Ignore errors if they weren't signed in with Google
    }
    await _supabase.auth.signOut();
  }

  // --- Get user display info ---
  String? get userDisplayName =>
      currentUser?.userMetadata?['full_name'] as String? ??
      currentUser?.userMetadata?['name'] as String? ??
      currentUser?.phone;

  String? get userEmail => currentUser?.email;
  String? get userPhone => currentUser?.phone;
  String? get userAvatarUrl =>
      currentUser?.userMetadata?['avatar_url'] as String?;
}
