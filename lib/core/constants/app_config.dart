/// アプリ全体の設定・APIキー。
/// 本番では --dart-define や .env / flutter_dotenv で注入し、
/// リポジトリには実キーをコミットしないこと。
class AppConfig {
  /// OpenRouteService の APIキー（無料・課金不要）。徒歩ルート検索で使用。
  /// https://openrouteservice.org/dev/ で取得し、
  /// `--dart-define=ORS_API_KEY=...` で注入する。
  /// 地図タイル（OpenStreetMap）はキー不要。
  static const String orsApiKey =
      String.fromEnvironment('ORS_API_KEY', defaultValue: '');

  /// AdMob バナー広告ユニットID（テストID）。
  static const String admobBannerTestId =
      'ca-app-pub-3940256099942544/6300978111';

  /// 課金プロダクトID。
  static const String iapSubscriptionMonthly = 'shadewalk_premium_monthly';
  static const String iapFutureRouteOneTime = 'shadewalk_future_route';
}
