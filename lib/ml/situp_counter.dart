import 'dart:math';

class SitUpCounter {
  int _reps = 0;
  bool _isUp = false;

  DateTime _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ✅ REALISTIC CAMERA-BASED THRESHOLDS
  static const double downAngle = 135; // lying down
  static const double upAngle = 95; // crunch position

  // ✅ HIP MOVEMENT TOLERANCE (normalized MoveNet coords)
  static const double hipMoveTolerance = 0.15;

  static const int minRepGapMs = 700;

  double? _lastHipY;

  int get reps => _reps;

  void reset() {
    _reps = 0;
    _isUp = false;
    _lastHipY = null;
    _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// ✅ SINGLE PARAMETER — MoveNet keypoints map
  void update(Map<String, Point<double>> kps) {
    // ✅ USE WHICHEVER SIDE IS VISIBLE
    final shoulder = kps['left_shoulder'] ?? kps['right_shoulder'];
    final hip = kps['left_hip'] ?? kps['right_hip'];
    final knee = kps['left_knee'] ?? kps['right_knee'];

    if (shoulder == null || hip == null || knee == null) return;

    // 🚫 Cheat detection (excessive hip lift)
    if (_lastHipY != null) {
      if ((hip.y - _lastHipY!).abs() > hipMoveTolerance) return;
    }
    _lastHipY = hip.y;

    final angle = _calculateAngle(shoulder, hip, knee);

    // 🔍 DEBUG (TEMP — remove later)
    print('angle=${angle.toStringAsFixed(1)}  isUp=$_isUp  reps=$_reps');

    final now = DateTime.now();
    final canCount = now.difference(_lastRepTime).inMilliseconds > minRepGapMs;

    // 🔼 Going UP
    if (!_isUp && angle < upAngle) {
      _isUp = true;
    }

    // 🔽 Coming DOWN → count rep
    if (_isUp && angle > downAngle && canCount) {
      _reps++;
      _lastRepTime = now;
      _isUp = false;
    }
  }

  // ✅ PURE DART ANGLE MATH (NO Flutter / Offset)
  double _calculateAngle(Point<double> a, Point<double> b, Point<double> c) {
    final abx = a.x - b.x;
    final aby = a.y - b.y;
    final cbx = c.x - b.x;
    final cby = c.y - b.y;

    final dot = abx * cbx + aby * cby;
    final magAB = sqrt(abx * abx + aby * aby);
    final magCB = sqrt(cbx * cbx + cby * cby);

    final cosAngle = (dot / (magAB * magCB + 1e-6)).clamp(-1.0, 1.0);

    return acos(cosAngle) * 180 / pi;
  }
}
