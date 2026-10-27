/// Compass heading helpers: direction words and relative turns.
class CompassHelper {
  /// Convert heading degrees to a human-readable direction.
  static String headingToWord(double deg) {
    deg = deg % 360;
    if (deg < 22.5 || deg >= 337.5) return 'north';
    if (deg < 67.5)  return 'north-east';
    if (deg < 112.5) return 'east';
    if (deg < 157.5) return 'south-east';
    if (deg < 202.5) return 'south';
    if (deg < 247.5) return 'south-west';
    if (deg < 292.5) return 'west';
    return 'north-west';
  }

  /// Returns "left", "right", "ahead", or "behind" given the user's current
  /// heading [userHeading] and the required [targetHeading] (both in degrees).
  static String relativeDirection(double userHeading, double targetHeading) {
    double diff = (targetHeading - userHeading) % 360;
    if (diff < 0) diff += 360;

    if (diff < 30 || diff > 330) return 'straight ahead';
    if (diff >= 30 && diff < 150) return 'to your right';
    if (diff >= 150 && diff < 210) return 'behind you';
    return 'to your left';
  }

  /// Normalise heading to 0–360 range.
  static double normalise(double deg) {
    deg = deg % 360;
    if (deg < 0) deg += 360;
    return deg;
  }

  /// Distance between two headings (always 0–180).
  static double headingDiff(double a, double b) {
    double d = (a - b).abs() % 360;
    if (d > 180) d = 360 - d;
    return d;
  }

  /// Returns a turn instruction ("Turn left", "Turn right", "Turn slightly left", "Turn slightly right", "Turn around", or "Continue straight")
  /// when transitioning from [fromHeading] to [toHeading].
  static String turnInstruction(double fromHeading, double toHeading) {
    double diff = (toHeading - fromHeading) % 360;
    if (diff < 0) diff += 360;

    if (diff <= 25 || diff >= 335) return 'Continue straight';
    if (diff > 25 && diff < 65) return 'Bear slightly right';
    if (diff >= 65 && diff <= 125) return 'Turn right';
    if (diff > 125 && diff < 160) return 'Make a sharp right';
    if (diff >= 160 && diff <= 200) return 'Turn around';
    if (diff > 200 && diff < 235) return 'Make a sharp left';
    if (diff >= 235 && diff <= 295) return 'Turn left';
    return 'Bear slightly left';
  }

}
