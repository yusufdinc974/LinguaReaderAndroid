import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../services/subscription_service.dart';
import '../../core/constants/app_colors.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Offerings? _offerings;
  bool _isLoading = true;
  bool _isPurchasing = false;
  int _selectedIndex = 1; // Default: Yearly (best value)

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offerings = await SubscriptionService.getOfferings();
    if (mounted)
      setState(() {
        _offerings = offerings;
        _isLoading = false;
      });
  }

  List<Package> get _packages {
    final current = _offerings?.current;
    if (current == null) return [];
    // Order: Monthly, Yearly, Lifetime
    final all = <Package>[
      ...current.monthly != null ? [current.monthly!] : [],
      ...current.annual != null ? [current.annual!] : [],
      ...current.lifetime != null ? [current.lifetime!] : [],
    ];
    return all;
  }

  Future<void> _purchase() async {
    final pkgs = _packages;
    if (pkgs.isEmpty || _selectedIndex >= pkgs.length) return;

    setState(() => _isPurchasing = true);
    try {
      final result = await SubscriptionService.purchase(pkgs[_selectedIndex]);
      if (result != null && mounted) {
        Navigator.of(context).pop(true); // Signal success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Welcome to Premium!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Purchase failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _isPurchasing = true);
    try {
      final result = await SubscriptionService.restorePurchases();
      if (mounted) {
        final hasPremium =
            result != null && SubscriptionService.hasPremiumEntitlement(result);
        if (hasPremium) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('✅ Purchase restored!'),
                backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active subscription found.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Restore failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1040), Color(0xFF0D0D1A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Header
                      const Icon(Icons.workspace_premium,
                          color: Color(0xFFFFD700), size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'LinguaReader Premium',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Unlock everything. Learn faster.',
                        style: TextStyle(color: Colors.white60, fontSize: 15),
                      ),
                      const SizedBox(height: 32),

                      // Feature list
                      _featureRow('Unlimited word lists & vocabulary', true),
                      _featureRow('Unlimited SRS flashcard reviews', true),
                      _featureRow('Cloud sync across all devices', true),
                      _featureRow('Full statistics & quiz history', true),
                      _featureRow('PDF cloud library storage', true),
                      const SizedBox(height: 32),

                      // Packages
                      if (_isLoading)
                        const CircularProgressIndicator(color: Colors.white)
                      else if (_packages.isEmpty)
                        const Text('Products unavailable. Please try later.',
                            style: TextStyle(color: Colors.white60))
                      else
                        Column(
                          children: List.generate(_packages.length, (i) {
                            final pkg = _packages[i];
                            final isYearly =
                                pkg.packageType == PackageType.annual;
                            final isSelected = _selectedIndex == i;

                            return GestureDetector(
                              onTap: () => setState(() => _selectedIndex = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withOpacity(0.25)
                                      : Colors.white.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.white24,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white54,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                _packageTitle(pkg),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              if (isYearly) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20),
                                                  ),
                                                  child: const Text(
                                                    'BEST VALUE',
                                                    style: TextStyle(
                                                      color: Colors.black,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _packageSubtitle(pkg),
                                            style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      pkg.storeProduct.priceString,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),

                      const SizedBox(height: 24),

                      // CTA Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isPurchasing ? null : _purchase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isPurchasing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Unlock Premium',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isPurchasing ? null : _restore,
                        child: const Text('Restore Purchases',
                            style: TextStyle(color: Colors.white54)),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Cancel anytime. Subscriptions auto-renew until cancelled.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _packageTitle(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return 'Monthly';
      case PackageType.annual:
        return 'Yearly';
      case PackageType.lifetime:
        return 'Lifetime';
      default:
        return pkg.storeProduct.title;
    }
  }

  String _packageSubtitle(Package pkg) {
    switch (pkg.packageType) {
      case PackageType.monthly:
        return 'Billed monthly';
      case PackageType.annual:
        return 'Billed once a year — save ~58%';
      case PackageType.lifetime:
        return 'One-time purchase, forever';
      default:
        return '';
    }
  }

  Widget _featureRow(String text, bool included) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            included ? Icons.check_circle : Icons.cancel,
            color: included ? Colors.greenAccent : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}
