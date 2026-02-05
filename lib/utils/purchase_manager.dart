import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_manager.dart';

class PurchaseManager {
  static final PurchaseManager instance = PurchaseManager._internal();
  PurchaseManager._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  final String _productId = 'unlock_unkou';
  final String _prefKeyIsPremium = 'is_premium_user';

  // Observable state for UI and AdManager
  final ValueNotifier<bool> isPremium = ValueNotifier(false);

  Future<void> initialize() async {
    // 1. Load persisted state first (fast)
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.getBool(_prefKeyIsPremium) ?? false;
    isPremium.value = loaded;
    if (loaded) {
      AdManager.instance.disableAds();
    }

    // 2. Listen to purchase updates
    final purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdates,
      onDone: () {
        _subscription.cancel();
      },
      onError: (error) {
        debugPrint('PurchaseManager: Error listening to purchase stream: $error');
      },
    );

    // 3. If needed, we could restore purchases automatically or check available products here.
  }

  void _onPurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Show pending UI if needed
        debugPrint('PurchaseManager: Purchase pending...');
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint('PurchaseManager: Purchase error: ${purchaseDetails.error}');
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          debugPrint('PurchaseManager: Purchase success or restored: ${purchaseDetails.productID}');
          
          if (purchaseDetails.productID == _productId) {
            _setPremium(true);
            AdManager.instance.disableAds(); // Clear ads immediately
          }
        }

        if (purchaseDetails.pendingCompletePurchase) {
          _iap.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<void> _setPremium(bool value) async {
    isPremium.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyIsPremium, value);
  }

  /// Triggers the purchase flow
  Future<void> buyPremium() async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      debugPrint('PurchaseManager: Store not available');
      return;
    }

    final Set<String> ids = {_productId};
    final ProductDetailsResponse response = await _iap.queryProductDetails(ids);

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('PurchaseManager: Product not found: ${response.notFoundIDs}');
      // Handle error (alert dialog?)
      return;
    }

    if (response.productDetails.isEmpty) {
      debugPrint('PurchaseManager: No product details found.');
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);

    _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Restores purchases
  Future<void> restorePurchases() async {
    final bool available = await _iap.isAvailable();
    if (!available) {
       debugPrint('PurchaseManager: Store not available for restore');
       return;
    }
    await _iap.restorePurchases();
  }

  void dispose() {
    _subscription.cancel();
    isPremium.dispose();
  }
}
