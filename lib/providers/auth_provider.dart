import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Streams auth state changes — widgets watching this rebuild on login/logout
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Simple bool — true if a user session exists
final isLoggedInProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state.session != null,
    loading: () => Supabase.instance.client.auth.currentSession != null,
    error: (_, __) => false,
  );
});

/// Current Supabase user
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser;
});

// ---- Subscription ----

/// FutureProvider that checks premium status from RevenueCat
final isPremiumProvider = FutureProvider<bool>((ref) async {
  // Refresh when auth changes
  ref.watch(authStateProvider);
  return SubscriptionService.isPremium();
});
