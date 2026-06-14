import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ShadeWalk のブランドカラー。
/// くすみプラム × ダスティローズ × ウォームアイボリーの上品な配色。
class AppColors {
  AppColors._();

  static const Color plum = Color(0xFF6F5B7E); // 主役：くすみプラム
  static const Color rose = Color(0xFFC98A8A); // アクセント：ダスティローズ
  static const Color gold = Color(0xFFC9A36B); // 日向：ウォームゴールド
  static const Color ivory = Color(0xFFFBF8F6); // 背景：ウォームアイボリー
  static const Color cream = Color(0xFFF3ECE8); // 一段濃い背景
  static const Color ink = Color(0xFF332B36); // 文字：ディープチャコールプラム
  static const Color mist = Color(0xFF9A8FA0); // 補助テキスト

  // 地図オーバーレイ
  static const Color building = Color(0xFFB9A99B); // 建物：ミュートトープ
  static const Color shadow = Color(0xFF4A3B57); // 影：ディーププラム
  static const Color rain = Color(0xFF7FA8B8); // 雨天ルート：くすみブルー
  static const Color arcade = Color(0xFFD8A47F); // アーケード
  static const Color underground = Color(0xFF9C8576); // 地下道
}

class AppTheme {
  AppTheme._();

  /// ロゴ用の上品なセリフ書体（Playfair Display）。
  static TextStyle logo({double size = 18, Color color = AppColors.ink}) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
        color: color,
      );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.plum,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.plum,
      secondary: AppColors.rose,
      surface: AppColors.ivory,
      onSurface: AppColors.ink,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    // 本文は Noto Sans JP（クリーン）、見出しは Shippori Mincho（繊細な明朝）。
    final body = GoogleFonts.notoSansJpTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
    final textTheme = body.copyWith(
      titleLarge: GoogleFonts.shipporiMincho(
        textStyle: body.titleLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      titleMedium: GoogleFonts.shipporiMincho(
        textStyle: body.titleMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelLarge: body.labelLarge?.copyWith(letterSpacing: 0.6),
      bodyMedium: body.bodyMedium?.copyWith(height: 1.4),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.ivory,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        shadowColor: AppColors.plum.withValues(alpha: 0.18),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.plum,
        inactiveTrackColor: AppColors.plum.withValues(alpha: 0.15),
        thumbColor: AppColors.plum,
        overlayColor: AppColors.plum.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.plum,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.plum,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.plum,
          side: const BorderSide(color: AppColors.plum),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
