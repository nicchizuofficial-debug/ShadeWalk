# プラットフォーム設定・ビルド手順

> ネイティブ雛形（`android/` `ios/` `web/`）は `flutter create` 生成済み。
> Flutter SDK は `C:\src\flutter` に導入済み。`flutter pub get` 済み。

## 0. 前提（このマシンの状態）
- Flutter SDK 3.44.1 … `C:\src\flutter`（PATH 未登録なら下記で都度通す）
- Android SDK … `C:\Users\matsumoto1472\AppData\Local\Android\Sdk`
- JDK 17（Temurin）導入済み

## Android Studio で開く
このプロジェクトは Android Studio で**そのまま開けます**（`.idea` 設定・
`android/local.properties`・Flutter 実行構成 `main.dart` 生成済み）。

1. Android Studio に **Flutter / Dart プラグイン**を入れる
   （Settings → Plugins → "Flutter" を検索してインストール → 再起動）。
2. Settings → Languages & Frameworks → **Flutter** で
   Flutter SDK path に `C:\src\flutter` を設定。
3. **File → Open** で `C:\claude_ShadeWalk`（リポジトリのルート）を開く。
   ※ `android/` サブフォルダではなく**ルート**を開くこと（Flutter プロジェクトのため）。
4. 右上のデバイス選択でエミュレータ/実機を選び、実行構成 `main.dart` で ▶ Run。
   - 地図(OSM)はキー不要。**ルート検索を使う場合のみ** ORS キーを渡す:
     Run → Edit Configurations → "Additional run args" に
     `--dart-define=ORS_API_KEY=＜キー＞`。

> Android Studio からの Run/ビルドは IDE 自身の JVM で動くため、
> Claude 実行環境で起きた loopback 問題（下記）は発生しません。

## 1. （参考）ネイティブ雛形の再生成（既存 lib/ は上書きされません）
```bash
cd C:\claude_ShadeWalk
flutter create . --org com.example.shadewalk --platforms=android,ios,web
flutter pub get
```

## 2. 静的解析・テスト
```bash
flutter analyze
flutter test          # test/shade_logic_test.dart が通ることを確認
```

## 3. ネイティブ設定（地図キー不要）
地図は OpenStreetMap タイル（`flutter_map`）のため **Google Maps APIキーは不要**。
必要な設定は権限・AdMob・minSdk のみ（いずれも編集済み）。

### Android — `android/app/src/main/AndroidManifest.xml`（編集済み）
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<!-- application 内: AdMob アプリID（公式テストID） -->
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-3940256099942544~3347511713"/>
```
minSdk は `android/app/build.gradle.kts` で `minSdk = maxOf(23, ...)` 設定済み。

### iOS — `ios/Runner/Info.plist`（編集済み）
```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-3940256099942544~1458002511</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>日陰ルート案内のため現在地を使用します。</string>
```
> 地図 SDK 初期化（GMSServices）は不要。AppDelegate もデフォルトのまま。

## 4. ルート検索キー（OpenRouteService・任意）
ルート検索を使う場合のみ、無料キーを https://openrouteservice.org/dev/ で取得し注入:
```bash
flutter run --dart-define=ORS_API_KEY=＜あなたのORSキー＞
```
> 無料枠（1日2000リクエスト程度）。課金・クレジットカード登録は不要。
> キー未設定でも地図表示・影計算・現在地は動作する（ルート検索のみ無効）。

## 5. 実行
```bash
flutter run --dart-define=ORS_API_KEY=＜あなたのORSキー＞
```

## スマホ画面をローカルで確認する

### (A) PC の Chrome でスマホ表示をエミュレート（実機不要・現在地も動く）
1. ターミナルで配信:
   ```
   flutter run -d web-server --web-port=8080
   ```
2. Chrome で `http://localhost:8080` を開く
3. **F12**（DevTools）→ 左上の**スマホ/タブレットのアイコン**（Toggle device toolbar, `Ctrl+Shift+M`）をクリック
4. 上部のデバイス選択で **iPhone / Pixel** などを選ぶ → スマホサイズで表示
   - `localhost` は安全な扱いなので**現在地（位置情報）も許可すれば動きます**

### (B) 実際のスマホで開く（同じ Wi-Fi 経由）
1. プロジェクト直下の **`run_mobile.bat` をダブルクリック**
   （または手動: `flutter run -d web-server --web-hostname=0.0.0.0 --web-port=8080`）
2. 画面に出る **このPCのIPアドレス**（例 `192.168.1.23`）を確認
3. スマホ（PCと同じ Wi-Fi）のブラウザで **`http://192.168.1.23:8080`** を開く
   - 初回は Windows ファイアウォールの許可ダイアログが出たら「アクセスを許可」
   - ※ `http://IP` 経由は安全な接続でないため**現在地取得はブラウザにブロックされます**（地図・影・⟳での建物取得は動作）。現在地まで試すなら (A) を使ってください

## 動作確認の流れ
1. 東京駅周辺の地図に建物（グレー）と影（紺）が表示される。
2. 下部スライダーで時刻を変えると影の向き・長さが変化する。
3. 地図を**長押し**すると目的地が立ち、徒歩ルート候補を取得。
   モードに応じて日陰（or 日向）スコア最良のルートが太線で強調される。
4. 上部トグルで「日陰優先 / 日向優先」を切替。
5. 未来時刻スライダー / ロックアイコンでペイウォールが表示される。

## 検証済み（Flutter 3.44.1 / Dart 3.12.1・OSM移行後）
- `flutter analyze` … **No issues found!**
- `flutter test` … **All tests passed!**（6件）
- `flutter build web` … **成功**（アプリ全体がコンパイル可能なことを確認）

> - 地図は OpenStreetMap タイル（`flutter_map`/`latlong2`）。Google Maps Platform 非依存・キー不要・課金不要。
> - ルートは OpenRouteService（`foot-walking`+代替ルート）。無料枠・キーのみ。
> - 太陽位置計算は `apsl_sun_calc`（`SunCalc.getPosition()`→`Map<String,num>`）。

## 実機セットアップ状況（2026-06-07・OSM移行後）
ネイティブ設定は**編集済み**:
- `android/app/src/main/AndroidManifest.xml` … INTERNET/位置情報権限・AdMob テストID（Maps キーは不要なので無し）
- `android/app/build.gradle.kts` … `minSdk = maxOf(23, ...)` 設定済み
- `ios/Runner/Info.plist` … AdMob テストID・位置情報説明 追記済み
- `ios/Runner/AppDelegate.swift` … デフォルト（Maps SDK 初期化不要）

> ⚠️ **このマシンの Claude 実行環境では `flutter build apk` / `flutter run`(Android) が動きません。**
> Gradle(Java NIO) のループバック自己パイプが Windows AppContainer 隔離でブロックされ
> `Unable to establish loopback connection` で失敗します（既知:
> https://github.com/anthropics/claude-code/issues/41432 ）。
> **あなたの通常の PowerShell/コマンドプロンプト（Claude外）か Android Studio で**
> 以下を実行してください（そちらでは正常に動きます）:
> ```powershell
> $env:Path = "C:\src\flutter\bin;" + $env:Path
> cd C:\claude_ShadeWalk
> flutter run --dart-define=ORS_API_KEY=＜ORSキー＞
> ```

## まだ必要な作業（実機ビルド）
- **Android 実機/エミュレータビルドには Android SDK が別途必要**
  （Android Studio 導入 → `flutter doctor --android-licenses`）。
- ネイティブ設定（権限・AdMob・minSdk）は編集済み。**地図キーは不要**。
- ルート検索を使うなら ORS キーを `--dart-define=ORS_API_KEY=...` で渡す。
