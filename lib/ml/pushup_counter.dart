import 'dart:math';

class PushUpCounter {
  int _reps = 0;
  bool _isDown = false;

  DateTime _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ✅ REALISTIC CAMERA-BASED PUSH-UP ANGLES
  static const double downAngle = 95; // bottom of push-up
  static const double upAngle = 160; // arms fully extended

  static const int minRepGapMs = 700;

  int get reps => _reps;

  void reset() {
    _reps = 0;
    _isDown = false;
    _lastRepTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// ✅ SINGLE PARAMETER — MoveNet keypoints map
  void update(Map<String, Point<double>> kps) {
    // ✅ USE WHICHEVER ARM IS VISIBLE
    final shoulder = kps['left_shoulder'] ?? kps['right_shoulder'];
    final elbow = kps['left_elbow'] ?? kps['right_elbow'];
    final wrist = kps['left_wrist'] ?? kps['right_wrist'];

    if (shoulder == null || elbow == null || wrist == null) return;

    final angle = _calculateAngle(shoulder, elbow, wrist);

    // 🔍 DEBUG (remove later)
    print(
      'angle=${angle.toStringAsFixed(1)}  '
      'isDown=$_isDown  reps=$_reps',
    );

    final now = DateTime.now();
    final canCount = now.difference(_lastRepTime).inMilliseconds > minRepGapMs;

    // 🔽 Going DOWN
    if (!_isDown && angle < downAngle) {
      _isDown = true;
    }

    // 🔼 Coming UP → count rep
    if (_isDown && angle > upAngle && canCount) {
      _reps++;
      _lastRepTime = now;
      _isDown = false;
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
