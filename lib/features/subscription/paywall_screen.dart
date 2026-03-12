import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../services/subscription_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/pixel_card.dart';

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
  bool _hasPremium = false;
  String? _currentProductId;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    try {
      final results = await Future.wait([
        SubscriptionService.getOfferings(),
        SubscriptionService.getCustomerInfo(),
      ]);
      final offerings = results[0] as Offerings?;
      final customerInfo = results[1] as CustomerInfo?;

      String? currentProductId;
      bool hasPremium = false;
      if (customerInfo != null) {
        hasPremium = SubscriptionService.hasPremiumEntitlement(customerInfo);
        final entitlements = customerInfo.entitlements.active;
        if (entitlements.containsKey(SubscriptionService.premiumEntitlement)) {
          currentProductId =
              entitlements[SubscriptionService.premiumEntitlement]
                  ?.productIdentifier;
        } else {
          for (final entry in entitlements.entries) {
            if (entry.key.toLowerCase() ==
                SubscriptionService.premiumEntitlement.toLowerCase()) {
              currentProductId = entry.value.productIdentifier;
              break;
            }
          }
        }
      }
      debugPrint('DEBUG: Offerings fetched: ${offerings?.all.keys}');
      debugPrint('DEBUG: Current offering: ${offerings?.current?.identifier}');
      debugPrint('DEBUG: Packages in current: ${offerings?.current?.availablePackages.length}');
      
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _hasPremium = hasPremium;
          _currentProductId = currentProductId;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('DEBUG: Error loading offerings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isCurrentPackage(Package pkg) {
    final productId = pkg.storeProduct.identifier;
    return _hasPremium &&
        _currentProductId != null &&
        productId == _currentProductId;
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
    if (_isCurrentPackage(pkgs[_selectedIndex])) return;

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
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const FoxSpriteAnimator(
                      animation: FoxAnimation.yawnSouth,
                      size: 90,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'LinguaReader Premium',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Unlock everything. Learn faster.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    // Feature Comparison
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildPlanCard(
                            title: 'Free',
                            isPremium: false,
                            features: [
                              _FeatureItem('10 Translations/day', included: false),
                              _FeatureItem('Max 3 Word Lists', included: false),
                              _FeatureItem('Max 5 PDF Imports', included: false),
                              _FeatureItem('Ask Gemini AI', included: false),
                              _FeatureItem('Cloud Sync', included: true),
                              _FeatureItem('Unlimited Reviews', included: true),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildPlanCard(
                            title: 'Premium',
                            isPremium: true,
                            features: [
                              _FeatureItem('Unlimited Translations', included: true),
                              _FeatureItem('Unlimited Word Lists', included: true),
                              _FeatureItem('Unlimited PDF Imports', included: true),
                              _FeatureItem('Ask Gemini AI', included: true),
                              _FeatureItem('Priority Support', included: true), // Replaced Cloud Sync with a placeholder premium feature
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (_isLoading)
                      const CircularProgressIndicator(color: AppColors.primary)
                    else if (_packages.isEmpty)
                      const Text('Products unavailable. Please try later.',
                          style: TextStyle(color: AppColors.textSecondary))
                    else
                      Column(
                        children: List.generate(_packages.length, (i) {
                          final pkg = _packages[i];
                          final isYearly =
                              pkg.packageType == PackageType.annual;
                          final isSelected = _selectedIndex == i;
                          final isCurrent = _isCurrentPackage(pkg);

                          return GestureDetector(
                            onTap: () => setState(() => _selectedIndex = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: PixelCard(
                                color: isSelected
                                    ? AppColors.primary.withOpacity(0.2)
                                    : Theme.of(context).colorScheme.surface,
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
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
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              if (isCurrent) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.success,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: const Text(
                                                    'CURRENT',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              if (isYearly) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.warning,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: const Text(
                                                    'BEST VALUE',
                                                    style: TextStyle(
                                                      color:
                                                          AppColors.background,
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
                                                color: AppColors.textSecondary,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    isCurrent
                                        ? const Text(
                                            'Current plan',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          )
                                        : Text(
                                            pkg.storeProduct.priceString,
                                            style: const TextStyle(
                                              color: AppColors.primaryLight,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isPurchasing ||
                                _packages.isEmpty ||
                                (_selectedIndex < _packages.length &&
                                    _isCurrentPackage(
                                        _packages[_selectedIndex]))
                            ? null
                            : _purchase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          disabledBackgroundColor: AppColors.surfaceHighlight,
                        ),
                        child: _isPurchasing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text(
                                _selectedIndex < _packages.length &&
                                        _isCurrentPackage(
                                            _packages[_selectedIndex])
                                    ? 'Current Plan'
                                    : _hasPremium
                                        ? 'Change Plan'
                                        : 'Unlock Premium',
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isPurchasing ? null : _restore,
                      child: const Text('Restore Purchases',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cancel anytime. Subscriptions auto-renew until cancelled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
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
        // Try to calculate discount dynamically if monthly is available
        final monthlyPkg = _packages.where((p) => p.packageType == PackageType.monthly).firstOrNull;
        if (monthlyPkg != null) {
          final monthlyPrice = monthlyPkg.storeProduct.price;
          final annualPrice = pkg.storeProduct.price;
          if (monthlyPrice > 0 && annualPrice > 0) {
            final expectedAnnualPrice = monthlyPrice * 12;
            final discount = ((expectedAnnualPrice - annualPrice) / expectedAnnualPrice * 100).round();
            if (discount > 0) {
              return 'Billed once a year — save ~$discount%';
            }
          }
        }
        return 'Billed once a year';
      case PackageType.lifetime:
        return 'One-time purchase, forever';
      default:
        return '';
    }
  }

  Widget _buildPlanCard({
    required String title,
    required bool isPremium,
    required List<_FeatureItem> features,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isPremium ? AppColors.primary.withOpacity(0.1) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPremium ? AppColors.primary : AppColors.border,
          width: isPremium ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: isPremium ? AppColors.primaryLight : AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isPremium
                          ? Icons.check_circle_rounded
                          : (f.included ? Icons.check_circle_rounded : Icons.lock_outline),
                      color: isPremium
                          ? AppColors.primaryLight
                          : (f.included ? AppColors.success : AppColors.textTertiary),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f.text,
                        style: TextStyle(
                          color: isPremium ? AppColors.textPrimary : (f.included ? AppColors.textSecondary : AppColors.textTertiary),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _FeatureItem {
  final String text;
  final bool included;

  _FeatureItem(this.text, {required this.included});
}
