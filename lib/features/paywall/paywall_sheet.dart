import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../monetization/iap/purchase_service.dart';

/// プレミアム機能の購入を促すボトムシート（上品な世界観）。
Future<void> showPaywall(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _PaywallContent(),
  );
}

class _PaywallContent extends StatelessWidget {
  const _PaywallContent();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PurchaseService>();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCF6F4), AppColors.ivory],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.mist.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.rose.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.rose, size: 22),
              ),
              const SizedBox(width: 12),
              Text('ShadeWalk Premium',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '日焼け・暑さを、もっとかしこく避ける。',
            style: TextStyle(color: AppColors.mist, fontSize: 13),
          ),
          const SizedBox(height: 20),
          const _Feature(
              icon: Icons.schedule, text: '未来の日時で日陰ルートを検索（明日14時など）'),
          const _Feature(
              icon: Icons.umbrella_outlined,
              text: '雨の日はアーケード・地下道を優先'),
          const _Feature(icon: Icons.block_flipped, text: '広告なしの快適表示'),
          const SizedBox(height: 24),
          if (!service.available)
            Text('現在ストアに接続できません。後でお試しください。',
                style: TextStyle(color: Theme.of(context).colorScheme.error))
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => service.buyMonthly(),
                child: Text(_priceLabel(service, 'shadewalk_premium_monthly',
                    fallback: '月額プランで解放する')),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => service.buyFutureRoute(),
                child: Text(_priceLabel(service, 'shadewalk_future_route',
                    fallback: '買い切りで解放する')),
              ),
            ),
          ],
          const SizedBox(height: 14),
          // デモ用：購入せずに有料機能を体験できる（動作確認用）
          Center(
            child: TextButton.icon(
              onPressed: () {
                service.setDemoPremium(true);
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('デモで体験する（購入なし）'),
              style: TextButton.styleFrom(foregroundColor: AppColors.mist),
            ),
          ),
        ],
      ),
    );
  }

  String _priceLabel(PurchaseService s, String id, {required String fallback}) {
    for (final p in s.products) {
      if (p.id == id) return '${p.title} ${p.price}';
    }
    return fallback;
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.plum),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14.5)),
          ),
        ],
      ),
    );
  }
}
