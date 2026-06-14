// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// ShadeWalk アプリアイコン生成スクリプト。
/// wb_twilight（薄明）モチーフ：地平線から昇る太陽＋光線。
/// カラー：プラム背景 / ローズ太陽 / ゴールド光線 / アイボリー地平線
///
/// 実行: dart run tool/generate_icon.dart
void main() {
  final size = 1024;

  // ---- パレット ----
  final bgTop    = img.ColorRgba8(0x6F, 0x5B, 0x7E, 0xFF); // plum
  final bgBottom = img.ColorRgba8(0x4A, 0x3B, 0x57, 0xFF); // dark plum
  final roseSun  = img.ColorRgba8(0xC9, 0x8A, 0x8A, 0xFF); // rose
  final goldRay  = img.ColorRgba8(0xC9, 0xA3, 0x6B, 0xFF); // gold
  final ivory    = img.ColorRgba8(0xFB, 0xF8, 0xF6, 0xE0); // ivory (semi)

  final image = img.Image(width: size, height: size);

  // ---- 背景グラデーション（上：plum → 下：dark plum）----
  for (int y = 0; y < size; y++) {
    final t = y / size;
    final r = (bgTop.r + (bgBottom.r - bgTop.r) * t).round().clamp(0, 255);
    final g = (bgTop.g + (bgBottom.g - bgTop.g) * t).round().clamp(0, 255);
    final b = (bgTop.b + (bgBottom.b - bgTop.b) * t).round().clamp(0, 255);
    for (int x = 0; x < size; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // ---- レイアウト定数 ----
  final cx = size / 2;            // 水平中心
  final cy = size / 2 + 60.0;    // 地平線の y 座標（中央より少し下）
  final sunR = 190.0;             // 太陽の半径
  final sunCy = cy - sunR * 0.6; // 太陽の中心（地平線の上）

  // ---- 光線（gold, 地平線より上のみ, 30°刻み）----
  final rayInner = sunR + 30.0;
  final rayOuter = sunR + 120.0;
  final rayWidth = 18;
  for (int deg = -150; deg <= 150; deg += 30) {
    final rad = deg * math.pi / 180;
    final x1 = (cx + rayInner * math.sin(rad)).round();
    final y1 = (sunCy - rayInner * math.cos(rad)).round();
    final x2 = (cx + rayOuter * math.sin(rad)).round();
    final y2 = (sunCy - rayOuter * math.cos(rad)).round();
    img.drawLine(image,
        x1: x1, y1: y1, x2: x2, y2: y2,
        color: goldRay, thickness: rayWidth,
        antialias: true);
  }

  // ---- 太陽（rose 塗りつぶし円）----
  img.fillCircle(image,
      x: cx.round(), y: sunCy.round(), radius: sunR.round(),
      color: roseSun);

  // ---- 地平線（ivory 線）----
  img.drawLine(image,
      x1: 80, y1: cy.round(),
      x2: size - 80, y2: cy.round(),
      color: ivory, thickness: 12, antialias: true);

  // ---- 地平線より下の太陽を隠す（背景色で塗りつぶし）----
  for (int y = cy.round(); y < size; y++) {
    final t = y / size;
    final r = (bgTop.r + (bgBottom.r - bgTop.r) * t).round().clamp(0, 255);
    final g = (bgTop.g + (bgBottom.g - bgTop.g) * t).round().clamp(0, 255);
    final b = (bgTop.b + (bgBottom.b - bgTop.b) * t).round().clamp(0, 255);
    for (int x = 0; x < size; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // 地平線を再描画（上書きされたので）
  img.drawLine(image,
      x1: 80, y1: cy.round(),
      x2: size - 80, y2: cy.round(),
      color: ivory, thickness: 12, antialias: true);

  // ---- PNG 保存 ----
  final out = File('assets/icon/app_icon.png');
  out.writeAsBytesSync(img.encodePng(image));
  print('✓ Generated: ${out.path}  (${size}x$size px)');
}
