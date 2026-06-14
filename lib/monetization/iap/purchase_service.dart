import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants/app_config.dart';

/// 課金管理。プレミアム解放状態を保持し、購入・復元を扱う。
///
/// 解放される機能:
///  - 未来時間のルート検索（例: 明日14時の日陰ルート）
///  - 雨天時のアーケード・地下道優先ルート
///
/// NOTE: 本番ではレシート検証（App Store / Play / 自前サーバ）を必ず行うこと。
/// ここでは購入完了をもってローカルに解放する簡易実装。
class PurchaseService extends ChangeNotifier {
  PurchaseService({InAppPurchase? iap})
      : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  static const _productIds = <String>{
    AppConfig.iapSubscriptionMonthly,
    AppConfig.iapFutureRouteOneTime,
  };

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  /// デモ用にプレミアム機能を解放/解除する（購入なしで動作確認するため）。
  /// 本番では使わない。
  void setDemoPremium(bool value) {
    if (_isPremium == value) return;
    _isPremium = value;
    notifyListeners();
  }

  bool _available = false;
  bool get available => _available;

  List<ProductDetails> _products = const [];
  List<ProductDetails> get products => _products;

  /// 起動時に呼ぶ。商品情報の取得と購入ストリームの購読を行う。
  Future<void> init() async {
    _available = await _iap.isAvailable();
    if (!_available) {
      notifyListeners();
      return;
    }

    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (e) => debugPrint('purchaseStream error: $e'),
    );

    final response = await _iap.queryProductDetails(_productIds);
    _products = response.productDetails;
    notifyListeners();

    // 過去購入の復元（買い切り・サブスクの再アクティブ化）。
    await _iap.restorePurchases();
  }

  ProductDetails? _productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 月額サブスクを購入。
  Future<void> buyMonthly() => _buy(AppConfig.iapSubscriptionMonthly);

  /// 未来時間ルートの買い切りを購入。
  Future<void> buyFutureRoute() => _buy(AppConfig.iapFutureRouteOneTime);

  Future<void> _buy(String productId) async {
    final product = _productById(productId);
    if (product == null) return;
    final param = PurchaseParam(productDetails: product);
    if (productId == AppConfig.iapSubscriptionMonthly) {
      await _iap.buyNonConsumable(purchaseParam: param);
    } else {
      // 買い切り（再購入不可の機能解放）は non-consumable 扱い。
      await _iap.buyNonConsumable(purchaseParam: param);
    }
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // TODO: ここでサーバ/ストアのレシート検証を行う。
          if (_productIds.contains(p.productID)) {
            _isPremium = true;
            notifyListeners();
          }
          break;
        case PurchaseStatus.error:
          debugPrint('purchase error: ${p.error}');
          break;
        case PurchaseStatus.pending:
        case PurchaseStatus.canceled:
          break;
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
