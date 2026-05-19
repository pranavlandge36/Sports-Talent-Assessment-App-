// lib/home_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:sports/activities/pushups.dart';
import 'package:sports/activities/situps_page.dart';
import 'package:sports/activities/verticaljump.dart';
import 'package:sports/activities/shuttle_run_page.dart';
import 'package:sports/activities/endurance_run_page.dart';
import 'package:sports/settings_page.dart';
import 'package:sports/leaderboard_page.dart'; // <- added import

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  String? userName;
  String? _photoUrl;
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;

  late final AnimationController _anim;

  // bottom nav selected index: 0 = Home, 1 = Leaderboard
  int _selectedIndex = 0;

  final List<_Activity> activities = const [
    _Activity(key: 'pushups', title: 'Push-ups', unit: 'reps'),
    _Activity(key: 'situps', title: 'Sit-ups', unit: 'reps'),
    _Activity(key: 'vertical_jump', title: 'Vertical Jump', unit: 'cm'),
    _Activity(key: 'shuttle_run', title: 'Shuttle Run (5-10-5)', unit: 's'),
    _Activity(key: 'endurance_run', title: 'Endurance Run (1.6 km)', unit: 's'),
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();

      setState(() {
        userName =
            (snap.data()?['name'] ?? u.displayName ?? u.email ?? 'Athlete')
                .toString();
        _photoUrl = (snap.data()?['photoUrl'] ?? snap.data()?['photourl'] ?? '')
            .toString();
        if (_photoUrl != null && _photoUrl!.trim().isEmpty) _photoUrl = null;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = e.toString();
      });
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pop(context);
  }

  /// For Option C:
  ///  - Best Score (highest score)
  ///  - Latest Attempt (most recent timestamp)
  Future<_UserActivityStats> _fetchStats(String key) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _UserActivityStats.empty();

    // Best score query
    final bestQ = await FirebaseFirestore.instance
        .collection('assessments')
        .where('userId', isEqualTo: uid)
        .where('activityKey', isEqualTo: key)
        .orderBy('score', descending: true)
        .limit(1)
        .get();

    // Latest attempt query
    final latestQ = await FirebaseFirestore.instance
        .collection('assessments')
        .where('userId', isEqualTo: uid)
        .where('activityKey', isEqualTo: key)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    final best = bestQ.docs.isNotEmpty ? bestQ.docs.first.data() : null;
    final last = latestQ.docs.isNotEmpty ? latestQ.docs.first.data() : null;

    return _UserActivityStats(bestScoreDoc: best, latestDoc: last);
  }

  void _openActivity(_Activity a) {
    switch (a.key) {
      case 'pushups':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PushUpsPage()),
        );
        return;
      case 'situps':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SitUpsPage()),
        );
        return;
      case 'vertical_jump':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VerticalJumpPage()),
        );
        return;
      case 'shuttle_run':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ShuttleRunPage()),
        );
        return;
      case 'endurance_run':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EnduranceRunPage()),
        );
        return;
      default:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Page not implemented')));
    }
  }

  void _onNavTap(int index) {
    // home (0) and leaderboard (1)
    if (index == _selectedIndex) return;

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final initials = _initialsOf(
      userName ?? user?.displayName ?? user?.email ?? 'Athlete',
    );

    // Body for Home screen
    final Widget homeBody = SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _HeaderCard(
              userName: userName,
              initials: initials,
              anim: _anim,
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
              onLogout: _logout,
              photoUrl: _photoUrl,
            ),
          ),

          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : hasError
                ? Center(
                    child: Text(
                      errorMessage == null || errorMessage!.isEmpty
                          ? "Failed to load."
                          : "Failed to load: $errorMessage",
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: ListView.separated(
                      itemCount: activities.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final a = activities[i];
                        return ActivityCard(
                          activity: a,
                          loader: () => _fetchStats(a.key),
                          onTap: () => _openActivity(a),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );

    // If leaderboard selected, show LeaderboardPage directly inside body.
    final Widget bodyWidget = (_selectedIndex == 0)
        ? homeBody
        : const LeaderboardPage();

    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      body: bodyWidget,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        backgroundColor: const Color(0xFF071018),
        selectedItemColor: Colors.lightGreenAccent,
        unselectedItemColor: Colors.white70,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events),
            label: 'Leaderboard',
          ),
        ],
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

// ============================================================================
// MODEL FOR ACTIVITY STATS
// ============================================================================
class _UserActivityStats {
  final Map<String, dynamic>? bestScoreDoc;
  final Map<String, dynamic>? latestDoc;

  _UserActivityStats({required this.bestScoreDoc, required this.latestDoc});

  factory _UserActivityStats.empty() =>
      _UserActivityStats(bestScoreDoc: null, latestDoc: null);
}

// ============================================================================
// HEADER WIDGET (now supports photoUrl)
// ============================================================================
class _HeaderCard extends StatelessWidget {
  final String? userName;
  final String initials;
  final AnimationController anim;
  final VoidCallback onSettings;
  final Future<void> Function() onLogout;
  final String? photoUrl; // added

  const _HeaderCard({
    required this.userName,
    required this.initials,
    required this.anim,
    required this.onSettings,
    required this.onLogout,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final name = userName ?? "Athlete";

    Widget avatarContent;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      avatarContent = ClipOval(
        child: Image.network(
          photoUrl!,
          fit: BoxFit.cover,
          width: 68,
          height: 68,
          // graceful fallback if network fails
          errorBuilder: (_, __, ___) => _initialsCircle(),
        ),
      );
    } else {
      avatarContent = _initialsCircle();
    }

    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1220), Color(0xFF072235)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.95, end: 1.0).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOut),
                  ),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: const Color(0xFF0D2733),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: avatarContent,
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Welcome back,",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // small settings button with edit icon (consistent with SettingsPage)
                InkWell(
                  onTap: onSettings,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white12,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.settings,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                InkWell(
                  onTap: () async => await onLogout(),
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white12,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.logout,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _initialsCircle() {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ============================================================================
// ACTIVITY CARD (BEST + LATEST)
// ============================================================================
class ActivityCard extends StatelessWidget {
  final _Activity activity;
  final Future<_UserActivityStats> Function() loader;
  final VoidCallback onTap;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.loader,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_UserActivityStats>(
      future: loader(),
      builder: (_, snap) {
        String best = "No attempts yet";
        String latest = "";
        double progress = 0.0;

        if (snap.hasData) {
          final stats = snap.data!;

          // best score text
          if (stats.bestScoreDoc != null) {
            final s = stats.bestScoreDoc!;
            final score = s['score'];
            best = "Best: $score ${activity.unit}";

            final parsed = double.tryParse(score.toString()) ?? 0;
            progress = (parsed.clamp(0, 100) / 100);
          }

          // latest attempt text
          if (stats.latestDoc != null) {
            final ts = stats.latestDoc!['timestamp'];
            final date = _fmt(ts);
            latest = "Latest: $date";
          }
        } else if (snap.connectionState == ConnectionState.waiting) {
          best = "Loading...";
        } else if (snap.hasError) {
          best = "Error loading stats";
        }

        return Material(
          color: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 6,
          shadowColor: Colors.black45,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _icon(activity.key),
                  const SizedBox(width: 12),

                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          best,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        if (latest.isNotEmpty)
                          Text(
                            latest,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation(
                              Colors.lightGreenAccent.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),
                  Icon(Icons.chevron_right, color: Colors.white54),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _icon(String k) {
    switch (k) {
      case 'pushups':
        return _ic(Icons.fitness_center);
      case 'situps':
        return _ic(Icons.self_improvement);
      case 'vertical_jump':
        return _ic(Icons.arrow_upward);
      case 'shuttle_run':
        return _ic(Icons.directions_run);
      case 'endurance_run':
        return _ic(Icons.track_changes);
      default:
        return _ic(Icons.sports);
    }
  }

  Widget _ic(IconData i) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B2A33), Color(0xFF0E1820)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(i, color: Colors.white, size: 28),
    );
  }

  static String _fmt(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return "${d.day}/${d.month}/${d.year}";
    }
    return "";
  }
}

// ============================================================================
// MODEL CLASS
// ============================================================================
class _Activity {
  final String key;
  final String title;
  final String unit;
  const _Activity({required this.key, required this.title, required this.unit});
}
