import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'monetization/iap/purchase_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();

  final purchaseService = PurchaseService()..init();

  runApp(
    ChangeNotifierProvider.value(
      value: purchaseService,
      child: const ShadeWalkApp(),
    ),
  );
}
