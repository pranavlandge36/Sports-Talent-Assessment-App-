// lib/activities/shuttle_run_record_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Record page for Shuttle Run (e.g. 5-10-5). UX mirrors pushup/endurance pages:
/// - large camera preview
/// - start recording -> stopwatch runs
/// - stop -> save elapsed seconds to Firestore (lower is better)
class ShuttleRunRecordPage extends StatefulWidget {
  const ShuttleRunRecordPage({super.key});

  @override
  State<ShuttleRunRecordPage> createState() => _ShuttleRunRecordPageState();
}

class _ShuttleRunRecordPageState extends State<ShuttleRunRecordPage>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isProcessing = false;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      final cam = _cameras?.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      if (cam == null) return;
      _cameraController = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('camera init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera not available')));
      }
    }
  }

  Widget _cameraPreviewWidget() {
    if (_cameraController == null) {
      return const Center(
        child: Text('Camera not ready', style: TextStyle(color: Colors.white)),
      );
    }
    if (!_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.center,
      child: SizedBox(
        width: _cameraController!.value.previewSize!.height,
        height: _cameraController!.value.previewSize!.width,
        child: CameraPreview(_cameraController!),
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    // mm:ss.t  (tenths)
    return '$mins:$secs.$millis';
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_isRecording) return;

    try {
      await _cameraController!.startVideoRecording();

      _stopwatch.reset();
      _stopwatch.start();
      _tickTimer?.cancel();
      _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });

      setState(() {
        _isRecording = true;
      });
    } on CameraException catch (e) {
      debugPrint('start recording error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start recording.')),
      );
    } catch (e) {
      debugPrint('start recording unexpected: $e');
    }
  }

  Future<void> _stopRecordingAndAnalyze() async {
    if (_cameraController == null || !_isRecording) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    XFile? raw;
    try {
      raw = await _cameraController!.stopVideoRecording();
    } on CameraException catch (e) {
      debugPrint('stop recording error: $e');
      setState(() => _isProcessing = false);
      return;
    } catch (e) {
      debugPrint('stop recording unexpected: $e');
      setState(() => _isProcessing = false);
      return;
    } finally {
      _tickTimer?.cancel();
      _tickTimer = null;
      _stopwatch.stop();
    }

    final tempFile = File(raw.path);

    try {
      // final score in seconds (integer). Lower time = better.
      final elapsedSeconds = _stopwatch.elapsed.inSeconds;

      await _saveAssessmentMetadata(
        activityKey: 'shuttle_run',
        score: elapsedSeconds,
        unit: 's',
        modelVersion: 'stopwatch-v1',
        confidence: 1.0,
        cheatScore: 0.0,
        compactAnalysis: {'method': 'stopwatch'},
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('analyze/save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Save failed.')));
      }
    } finally {
      setState(() => _isProcessing = false);
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<void> _saveAssessmentMetadata({
    required String activityKey,
    required num score,
    required String unit,
    required String modelVersion,
    required double confidence,
    required double cheatScore,
    Map<String, dynamic>? compactAnalysis,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final attemptId = const Uuid().v4();

    String platform = 'unknown';
    String osVersion = '';
    try {
      final info = DeviceInfoPlugin();
      final di = await info.deviceInfo;
      platform =
          di.data['name']?.toString() ??
          di.data['model']?.toString() ??
          'device';
      osVersion = di.data['version']?.toString() ?? '';
    } catch (_) {}

    final fingerprintSource =
        '$activityKey|$score|$modelVersion|$attemptId|${user.uid}';
    final fingerprintHash = sha256
        .convert(utf8.encode(fingerprintSource))
        .toString()
        .substring(0, 32);

    final docRef = FirebaseFirestore.instance.collection('assessments').doc();
    final payload = {
      'userId': user.uid,
      'displayName': user.displayName ?? user.email ?? 'Athlete',
      'activityKey': activityKey,
      'score': score,
      'unit': unit,
      'modelVersion': modelVersion,
      'confidence': confidence,
      'cheatScore': cheatScore,
      'deviceInfo': {'platform': platform, 'osVersion': osVersion},
      'attemptId': attemptId,
      'fingerprintHash': fingerprintHash,
      'analysisMetadata': compactAnalysis ?? {},
      'uploadStatus': 'uploaded',
      'timestamp': FieldValue.serverTimestamp(),
    };

    await docRef.set(payload);

    // Update best_scores doc atomically. For shuttle run, LOWER time is better.
    final bestRef = FirebaseFirestore.instance
        .collection('best_scores')
        .doc('${user.uid}_shuttle_run');
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(bestRef);
      if (!snap.exists) {
        tx.set(bestRef, {
          'userId': user.uid,
          'displayName': user.displayName ?? user.email ?? 'Athlete',
          'activityKey': activityKey,
          'score': score,
          'unit': unit,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        final existing = snap.data()!;
        final existingScore = (existing['score'] is num)
            ? (existing['score'] as num).toInt()
            : 1 << 30;
        if (score < existingScore) {
          tx.update(bestRef, {
            'score': score,
            'timestamp': FieldValue.serverTimestamp(),
            'displayName': user.displayName ?? user.email ?? 'Athlete',
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _cameraPreviewWidget();
    final elapsed = _stopwatch.elapsed;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Record Shuttle Run (5-10-5)'),
        backgroundColor: Colors.black,
        elevation: 1,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // large camera preview area
            Expanded(
              flex: 7,
              child: Stack(
                children: [
                  Positioned.fill(child: preview),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 140,
                    child: IgnorePointer(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xCC000000), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // elapsed time badge
                  Positioned(
                    top: 24,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _formatElapsed(elapsed),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              ' (5-10-5)',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_isRecording)
                    const Positioned(
                      top: 18,
                      left: 12,
                      child: _RecordingBadge(),
                    ),
                ],
              ),
            ),

            // controls
            Container(
              padding: const EdgeInsets.all(14),
              width: double.infinity,
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recording controls',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  if (_isProcessing) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : (_isRecording
                                    ? _stopRecordingAndAnalyze
                                    : _startRecording),
                          icon: Icon(
                            _isRecording
                                ? Icons.stop
                                : Icons.fiber_manual_record,
                          ),
                          label: Text(
                            _isRecording ? 'Stop & Save' : 'Start Recording',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording
                                ? Colors.redAccent
                                : Colors.white,
                            foregroundColor: _isRecording
                                ? Colors.white
                                : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isProcessing
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Place phone so athlete and course markers are visible for the whole attempt.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.circle, color: Colors.white, size: 10),
          SizedBox(width: 8),
          Text(
            'REC',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
