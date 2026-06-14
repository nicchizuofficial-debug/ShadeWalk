import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../map/map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _rayRotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _rayRotate = Tween<double>(begin: -0.08, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 600), _goToMap);
    });
  }

  void _goToMap() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MapScreen(),
        transitionDuration: const Duration(milliseconds: 700),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: anim,
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A3B57), // dark plum
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: RotationTransition(
                  turns: _rayRotate,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SunIcon(size: 120),
                      const SizedBox(height: 28),
                      Text(
                        'ShadeWalk',
                        style: AppTheme.logo(
                          size: 36,
                          color: const Color(0xFFFBF8F6),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '日陰・日向を選んで歩こう',
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFFFBF8F6).withValues(alpha: 0.7),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// アイコンと同じデザイン（プラム背景・ローズ太陽・ゴールド光線・アイボリー地平線）
/// を CustomPainter で描画するウィジェット。
class _SunIcon extends StatelessWidget {
  const _SunIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6F5B7E), Color(0xFF4A3B57)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC98A8A).withValues(alpha: 0.35),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: CustomPaint(painter: _IconPainter()),
    );
  }
}

class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final horizonY = h * 0.58;
    final sunCy = horizonY - h * 0.18;
    final sunR = w * 0.20;

    final goldPaint = Paint()
      ..color = const Color(0xFFC9A36B)
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 光線（地平線より上のみ）
    final rayInner = sunR + w * 0.04;
    final rayOuter = sunR + w * 0.14;
    for (int deg = -150; deg <= 150; deg += 30) {
      final rad = deg * math.pi / 180;
      final x1 = cx + rayInner * math.sin(rad);
      final y1 = sunCy - rayInner * math.cos(rad);
      final x2 = cx + rayOuter * math.sin(rad);
      final y2 = sunCy - rayOuter * math.cos(rad);
      if (y1 > horizonY && y2 > horizonY) continue;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), goldPaint);
    }

    // 太陽（ローズ）
    final sunPaint = Paint()
      ..color = const Color(0xFFC98A8A)
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, w, horizonY));
    canvas.drawCircle(Offset(cx, sunCy), sunR, sunPaint);
    canvas.restore();

    // 地平線（アイボリー）
    final horizonPaint = Paint()
      ..color = const Color(0xFFFBF8F6).withValues(alpha: 0.85)
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.12, horizonY),
      Offset(w * 0.88, horizonY),
      horizonPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
