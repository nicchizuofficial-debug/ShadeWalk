import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/map/map_screen.dart';

class ShadeWalkApp extends StatelessWidget {
  const ShadeWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShadeWalk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const MapScreen(),
    );
  }
}
