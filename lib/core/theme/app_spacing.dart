import 'package:flutter/widgets.dart';

/// 4-pt spacing scale + shared radii. Keeps rhythm consistent everywhere.
abstract final class Sp {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class Radii {
  static const Radius xs = Radius.circular(8);
  static const Radius sm = Radius.circular(12);
  static const Radius md = Radius.circular(18);
  static const Radius lg = Radius.circular(24);
  static const Radius xl = Radius.circular(32);
  static const Radius pill = Radius.circular(999);

  static const BorderRadius rSm = BorderRadius.all(sm);
  static const BorderRadius rMd = BorderRadius.all(md);
  static const BorderRadius rLg = BorderRadius.all(lg);
  static const BorderRadius rXl = BorderRadius.all(xl);
  static const BorderRadius rPill = BorderRadius.all(pill);
}
