import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:sports/ml/pose_estimator.dart';
import 'package:sports/ml/vertical_jump_counter.dart';

class VerticalJumpRecordPage extends StatefulWidget {
  const VerticalJumpRecordPage({super.key});

  @override
  State<VerticalJumpRecordPage> createState() => _VerticalJumpRecordPageState();
}

class _VerticalJumpRecordPageState extends State<VerticalJumpRecordPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _isRunning = false;
  bool _isProcessing = false;

  int _currentCm = 0;
  int _maxCm = 0;
  int _frameSkip = 0;

  late final PoseEstimator _pose;
  final VerticalJumpCounter _counter = VerticalJumpCounter();

  // ----------------------
  // Lifecycle
  // ----------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pose = PoseEstimator();
    _pose.load().then((_) => debugPrint('🔥 PoseEstimator READY'));
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  // ----------------------
  // Camera
  // ----------------------
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );

    _camera = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _camera!.initialize();
    if (mounted) setState(() {});
  }

  // ----------------------
  // Start / Stop
  // ----------------------
  Future<void> _start() async {
    if (_camera == null || _isRunning) return;

    _counter.reset();
    _currentCm = 0;
    _maxCm = 0;
    _frameSkip = 0;
    _isRunning = true;

    await _camera!.startImageStream(_onFrame);
    setState(() {});
  }

  Future<void> _stop() async {
    if (_camera == null || !_isRunning) return;

    _isRunning = false;
    await _camera!.stopImageStream();

    await _saveAssessment();
    if (mounted) Navigator.pop(context, true);
  }

  // ----------------------
  // Frame Processing
  // ----------------------
  Future<void> _onFrame(CameraImage image) async {
    if (_isProcessing || !_isRunning) return;

    _frameSkip++;
    if (_frameSkip % 3 != 0) return;

    _isProcessing = true;

    try {
      final keypoints = await _pose.process(image);
      if (keypoints == null) return;

      _counter.update(keypoints);

      final cm = _counter.maxJumpCm;
      if (cm != _maxCm) {
        setState(() {
          _currentCm = cm;
          _maxCm = cm;
        });
      }
    } catch (_) {
      // ignore bad frames
    } finally {
      _isProcessing = false;
    }
  }

  // ----------------------
  // Save to Firestore
  // ----------------------
  Future<void> _saveAssessment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final attemptId = const Uuid().v4();
    final fingerprint = sha256
        .convert(utf8.encode('vertical_jump|$_maxCm|$attemptId|${user.uid}'))
        .toString()
        .substring(0, 32);

    await FirebaseFirestore.instance.collection('assessments').add({
      'userId': user.uid,
      'displayName': user.displayName ?? user.email ?? 'Athlete',
      'activityKey': 'vertical_jump',
      'score': _maxCm,
      'unit': 'cm',
      'modelVersion': 'movenet-verticaljump-v1',
      'confidence': 0.9,
      'cheatScore': 0.05,
      'attemptId': attemptId,
      'fingerprintHash': fingerprint,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ----------------------
  // UI
  // ----------------------
  @override
  Widget build(BuildContext context) {
    if (_camera == null || !_camera!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Vertical Jump')),
      body: Column(
        children: [
          Expanded(child: CameraPreview(_camera!)),
          const SizedBox(height: 12),
          Text(
            'Current: $_currentCm cm',
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          Text(
            'Max: $_maxCm cm',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _isRunning ? _stop : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRunning ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_isRunning ? 'Stop & Save' : 'Start'),
            ),
          ),
        ],
      ),
    );
  }
}
