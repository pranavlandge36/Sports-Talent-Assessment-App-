import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_screen.dart';
import 'home_page.dart';
import 'admin/admin_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset('assets/intro.mp4')
      ..initialize().then((_) {
        _controller.setVolume(0);
        _controller.play();

        _controller.addListener(() {
          if (_controller.value.position >= _controller.value.duration &&
              mounted &&
              !_navigated) {
            _navigateNext();
          }
        });

        setState(() => _initialized = true);
      });

    Timer(const Duration(seconds: 5), () {
      if (mounted && !_navigated) {
        _navigateNext();
      }
    });
  }

  Future<void> _navigateNext() async {
    _navigated = true;

    final user = FirebaseAuth.instance.currentUser;

    Widget nextPage;

    if (user == null) {
      nextPage = const AuthScreen();
    } else {
      // VERY IMPORTANT: force refresh token
      await user.getIdToken(true);

      final idTokenResult = await user.getIdTokenResult();
      final claims = idTokenResult.claims;

      print("Claims: $claims");

      if (claims != null && claims['role'] == 'admin') {
        nextPage = const AdminDashboard();
      } else {
        nextPage = HomePage();
      }
    }

    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => nextPage));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildVideo() {
    if (!_initialized) return const SizedBox.shrink();

    final size = _controller.value.size;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideo(),
          Container(color: Colors.black.withOpacity(0.1)),
        ],
      ),
    );
  }
}
