import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart';

class SubscriptionService {
  static const String _revenueCatApiKey = 'goog_zPVjrEkhTrBTpyztXSGvuOyHVOw';

  // Product identifiers - must match what you create in Play Console
  static const String monthlyId = 'premium_monthly';
  static const String yearlyId = 'premium_yearly';
  static const String lifetimeId = 'premiumlifetime';

  // RevenueCat entitlement identifier
  static const String premiumEntitlement = 'premium';

  static Future<void> initialize() async {
    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.debug : LogLevel.error,
    );

    final config = PurchasesConfiguration(_revenueCatApiKey);
    await Purchases.configure(config);
  }

  /// Returns true if the user has an active premium entitlement
  static Future<bool> isPremium() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return hasPremiumEntitlement(customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService.isPremium error: $e');
      return false;
    }
  }

  static bool hasPremiumEntitlement(CustomerInfo customerInfo) {
    final active = customerInfo.entitlements.active;
    if (active.containsKey(premiumEntitlement)) return true;
    return active.keys.any(
      (key) => key.toLowerCase() == premiumEntitlement.toLowerCase(),
    );
  }

  /// Returns CustomerInfo for detailed entitlement info
  static Future<CustomerInfo?> getCustomerInfo() async {
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('SubscriptionService.getCustomerInfo error: $e');
      return null;
    }
  }

  /// Fetch available offerings (products) from RevenueCat
  static Future<Offerings?> getOfferings() async {
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('SubscriptionService.getOfferings error: $e');
      return null;
    }
  }

  /// Purchase a specific package
  static Future<CustomerInfo?> purchase(Package package) async {
    try {
      final result = await Purchases.purchasePackage(package);
      return result.customerInfo;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        return null; // User cancelled — not an error
      }
      rethrow;
    }
  }

  /// Restore previous purchases (for reinstalls / new devices)
  static Future<CustomerInfo?> restorePurchases() async {
    try {
      return await Purchases.restorePurchases();
    } catch (e) {
      debugPrint('SubscriptionService.restorePurchases error: $e');
      rethrow;
    }
  }

  /// Set the user ID in RevenueCat (call this after Supabase login)
  static Future<void> loginUser(String userId) async {
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('SubscriptionService.loginUser error: $e');
    }
  }

  /// Log out RevenueCat user (call this on Supabase sign-out)
  static Future<void> logoutUser() async {
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('SubscriptionService.logoutUser error: $e');
    }
  }
}
