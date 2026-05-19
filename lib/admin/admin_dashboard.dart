import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';

import '../auth_screen.dart';
import '../services/percentile_service.dart';
import '../services/recommendation_service.dart';
import 'athlete_profile_page.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                /// ===== TOP HEADER ROW =====
                Row(
                  children: [
                    /// Title takes available space
                    Expanded(
                      child: Text(
                        "SAI Talent Analytics",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    const SizedBox(width: 10),

                    /// Logout button stays fixed size
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text("Logout"),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                /// ===== DASHBOARD BODY =====
                const Expanded(child: HybridLeaderboardSection()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ================= HYBRID LEADERBOARD ================= */

class HybridLeaderboardSection extends StatefulWidget {
  const HybridLeaderboardSection({super.key});

  @override
  State<HybridLeaderboardSection> createState() =>
      _HybridLeaderboardSectionState();
}

class _HybridLeaderboardSectionState extends State<HybridLeaderboardSection> {
  final PercentileService _percentileService = PercentileService();
  final RecommendationService _recommendationService = RecommendationService();

  bool _loading = true;

  Map<String, List<Map<String, dynamic>>> _allSportGrouped = {};
  List<Map<String, dynamic>> _visiblePlayers = [];

  String _leaderboardSport = "";
  String _leaderboardGender = "all";
  String _graphGenderFilter = "all"; // all, male, female
  String _graphSportFilter = "all";

  Map<String, int> _sportCounts = {};

  final List<Color> _barColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.red,
    Colors.cyan,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  double safeNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return 0.0;
  }

  Future<void> _loadLeaderboard() async {
    final db = FirebaseFirestore.instance;
    Map<String, List<Map<String, dynamic>>> grouped = {};

    final usersSnapshot = await db.collection("users").get();

    for (var userDoc in usersSnapshot.docs) {
      final user = userDoc.data();
      final userId = userDoc.id;

      final age = user['age'];
      final gender = user['gender'];

      if (age == null || gender == null) continue;

      final height = safeNum(user['height']);
      final weight = safeNum(user['weight']);
      final chest = safeNum(user['chest']);

      final bestSnap = await db
          .collection('best_scores')
          .where('userId', isEqualTo: userId)
          .get();

      if (bestSnap.docs.isEmpty) continue;

      final normativeSnap = await db
          .collection('normative_data')
          .doc("${age}_$gender")
          .get();

      if (!normativeSnap.exists) continue;

      final normativeRaw = normativeSnap.data();

      if (normativeRaw == null || normativeRaw is! Map<String, dynamic>) {
        continue;
      }

      final normative = normativeRaw;

      Map<String, double> percentiles = {};
      Map<String, dynamic> bestTrials = {};

      for (var doc in bestSnap.docs) {
        final data = doc.data();
        final activityKey = data['activityKey'];
        if (activityKey == null) continue;

        final score = safeNum(data['score']);
        final unit = data['unit'];

        if (score == 0) continue;

        /// 🔥 ADD THIS — STORE RAW BEST TRIAL
        bestTrials[activityKey] = {"score": score, "unit": unit ?? ""};

        if (!normative.containsKey(activityKey)) continue;

        final activityDataRaw = normative[activityKey];
        if (activityDataRaw == null ||
            activityDataRaw is! Map<String, dynamic>) {
          continue;
        }

        final mean = safeNum(activityDataRaw['mean']);
        final std = safeNum(activityDataRaw['stdDev']);
        if (mean == 0 || std == 0) continue;

        bool lowerIsBetter =
            activityKey.contains("run") || activityKey.contains("sprint");

        final percentile = _percentileService.calculatePercentile(
          score: score,
          mean: mean,
          std: std,
          lowerIsBetter: lowerIsBetter,
        );

        percentiles[activityKey] = percentile;
      }

      if (percentiles.isEmpty) continue;

      final recommendation = _recommendationService.recommendSport(
        percentiles: percentiles,
        height: height,
        weight: weight,
        chest: chest,
      );

      final sport = recommendation['bestSport'];
      final score = safeNum(recommendation['score']);
      if (sport == null) continue;

      grouped.putIfAbsent(sport, () => []);
      grouped[sport]!.add({
        "id": userId,
        "name": user['name'] ?? "Unknown",
        "email": user['email'] ?? "",
        "score": score,
        "category": recommendation['category'] ?? "N/A",
        "sport": sport,
        "gender": gender.toString().toLowerCase(),
        "user": user,
        "bestTrials": bestTrials, // 🔥 IMPORTANT
      });
    }

    grouped.forEach((sport, players) {
      players.sort(
        (a, b) => ((b['score'] as double?) ?? 0).compareTo(
          (a['score'] as double?) ?? 0,
        ),
      );
    });

    if (!mounted) return;

    setState(() {
      _allSportGrouped = grouped;
      _leaderboardSport = grouped.keys.isNotEmpty ? grouped.keys.first : "";
      _updateLeaderboard();
      _updateGraphCounts();
      _loading = false;
    });
  }

  void _updateLeaderboard() {
    final players = _allSportGrouped[_leaderboardSport] ?? [];

    _visiblePlayers = players.where((p) {
      if (_leaderboardGender == "all") return true;
      return p['gender'] == _leaderboardGender;
    }).toList();
  }

  void _updateGraphCounts() {
    Map<String, int> counts = {};

    _allSportGrouped.forEach((sport, players) {
      if (_graphSportFilter != "all" && sport != _graphSportFilter) {
        return;
      }

      final filteredPlayers = players.where((p) {
        if (_graphGenderFilter == "all") return true;
        return p['gender'] == _graphGenderFilter;
      }).toList();

      if (filteredPlayers.isNotEmpty) {
        counts[sport] = filteredPlayers.length;
      }
    });

    _sportCounts = counts;
  }

  void _openProfile(Map<String, dynamic> player) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AthleteProfilePage(player: player)),
    );
  }

  List<BarChartGroupData> _buildSportBars() {
    int index = 0;
    return _sportCounts.entries.map((e) {
      final color = _barColors[index % _barColors.length];
      return BarChartGroupData(
        x: index++,
        barRods: [
          BarChartRodData(
            toY: e.value.toDouble(),
            width: 18,
            borderRadius: BorderRadius.circular(6),
            color: color,
          ),
        ],
      );
    }).toList();
  }

  Widget _styledDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: Colors.white,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return ListView(
      children: [
        /// ================= TITLE =================

        /// ================= FILTER CARD =================
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: _styledDropdown(
                  value: _graphSportFilter,
                  items: [
                    const DropdownMenuItem(
                      value: "all",
                      child: Text("All Sports"),
                    ),
                    ..._allSportGrouped.keys.map(
                      (sport) =>
                          DropdownMenuItem(value: sport, child: Text(sport)),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _graphSportFilter = val!;
                      _updateGraphCounts();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _styledDropdown(
                  value: _graphGenderFilter,
                  items: const [
                    DropdownMenuItem(value: "all", child: Text("All")),
                    DropdownMenuItem(value: "male", child: Text("Male")),
                    DropdownMenuItem(value: "female", child: Text("Female")),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _graphGenderFilter = val!;
                      _updateGraphCounts();
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 25),

        /// ================= CHART CARD =================
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barGroups: _buildSportBars(),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ),

        const SizedBox(height: 35),

        /// ================= LEADERBOARD TITLE =================
        const Text(
          "Leaderboard",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),

        const SizedBox(height: 15),

        /// ================= LEADERBOARD FILTER =================
        Row(
          children: [
            Expanded(
              child: _styledDropdown(
                value: _leaderboardSport,
                items: _allSportGrouped.keys
                    .map(
                      (sport) =>
                          DropdownMenuItem(value: sport, child: Text(sport)),
                    )
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _leaderboardSport = val!;
                    _updateLeaderboard();
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _styledDropdown(
                value: _leaderboardGender,
                items: const [
                  DropdownMenuItem(value: "all", child: Text("All")),
                  DropdownMenuItem(value: "male", child: Text("Male")),
                  DropdownMenuItem(value: "female", child: Text("Female")),
                ],
                onChanged: (val) {
                  setState(() {
                    _leaderboardGender = val!;
                    _updateLeaderboard();
                  });
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        /// ================= PLAYER CARDS =================
        ..._visiblePlayers.asMap().entries.map((entry) {
          int index = entry.key;
          var row = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Text(
                  "#${index + 1}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openProfile(row),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['name'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            _badge(row['sport'], Colors.orange),
                            _badge(row['category'], Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  ((row['score'] as double?) ?? 0.0).toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
