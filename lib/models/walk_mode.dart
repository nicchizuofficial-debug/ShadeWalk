/// 歩行モード。日陰優先（夏）か日向優先（冬）かを表す。
enum WalkMode {
  /// 日陰優先（夏・熱中症/日焼け対策）
  shade,

  /// 日向優先（冬・暖かさ重視）
  sun;

  String get label => switch (this) {
        WalkMode.shade => '日陰優先',
        WalkMode.sun => '日向優先',
      };

  WalkMode get toggled => this == WalkMode.shade ? WalkMode.sun : WalkMode.shade;
}
