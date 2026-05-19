// lib/activities/pushups_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'pushup_record_page.dart';

class PushUpsPage extends StatefulWidget {
  const PushUpsPage({super.key});

  @override
  State<PushUpsPage> createState() => _PushUpsPageState();
}

class _PushUpsPageState extends State<PushUpsPage> {
  int? _personalBest;
  String _personalBestWhen = '';
  List<_LeaderboardItem> _leaderboard = [];
  int? _myRank;
  bool _loading = true;
  final int _leaderboardLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadPersonalBestAndLeaderboard();
  }

  Future<void> _loadPersonalBestAndLeaderboard() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // personal best: try best_scores then fallback to assessments
      final bestDoc = await FirebaseFirestore.instance
          .collection('best_scores')
          .doc('${user.uid}_pushups')
          .get();

      if (bestDoc.exists) {
        final data = bestDoc.data()!;
        _personalBest = (data['score'] is num)
            ? (data['score'] as num).toInt()
            : null;
        _personalBestWhen = _formatTimestampCompact(data['timestamp']);
      } else {
        final q = await FirebaseFirestore.instance
            .collection('assessments')
            .where('userId', isEqualTo: user.uid)
            .where('activityKey', isEqualTo: 'pushups')
            .orderBy('score', descending: true)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          _personalBest = (d['score'] is num)
              ? (d['score'] as num).toInt()
              : null;
          _personalBestWhen = _formatTimestampCompact(d['timestamp']);
        } else {
          _personalBest = null;
          _personalBestWhen = '';
        }
      }

      // leaderboard (preferred from best_scores)
      final bestScoresSnapshot = await FirebaseFirestore.instance
          .collection('best_scores')
          .where('activityKey', isEqualTo: 'pushups')
          .orderBy('score', descending: true)
          .limit(_leaderboardLimit)
          .get();

      if (bestScoresSnapshot.docs.isNotEmpty) {
        _leaderboard = bestScoresSnapshot.docs.map((doc) {
          final d = doc.data();
          return _LeaderboardItem(
            userId: (d['userId'] ?? doc.id).toString(),
            name: (d['displayName'] ?? 'Player').toString(),
            score: (d['score'] is num) ? (d['score'] as num).toInt() : 0,
            timestamp: d['timestamp'],
          );
        }).toList();

        // Enrich with names from users collection if available
        await _enrichNamesForLeaderboard();

        if (_personalBest != null) {
          final higher = await FirebaseFirestore.instance
              .collection('best_scores')
              .where('activityKey', isEqualTo: 'pushups')
              .where('score', isGreaterThan: _personalBest)
              .get();
          _myRank = higher.docs.length + 1;
        } else {
          _myRank = null;
        }
      } else {
        await _computeLeaderboardFallback();
      }
    } catch (e, st) {
      debugPrint('Failed to load leaderboard: $e\n$st');
      await _computeLeaderboardFallback();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Try to replace the name field in each _LeaderboardItem with the canonical name
  // from the `users` collection. Non-fatal: if users docs don't exist we keep the
  // existing name (from best_scores or assessments).
  Future<void> _enrichNamesForLeaderboard() async {
    try {
      final db = FirebaseFirestore.instance;
      final ids = _leaderboard
          .map((it) => it.userId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isEmpty) return;

      // fetch user docs in parallel (avoid whereIn limits)
      final futures = ids
          .map((id) => db.collection('users').doc(id).get())
          .toList();
      final snaps = await Future.wait(futures);

      final Map<String, String> idToName = {};
      for (int i = 0; i < ids.length; i++) {
        final snap = snaps[i];
        final id = ids[i];
        if (snap.exists) {
          final data = snap.data();
          if (data != null) {
            final n = (data['name'] ?? '').toString();
            if (n.isNotEmpty) idToName[id] = n;
          }
        }
      }

      // apply names back into leaderboard list
      for (var i = 0; i < _leaderboard.length; i++) {
        final uid = _leaderboard[i].userId;
        final resolved = idToName[uid];
        if (resolved != null && resolved.isNotEmpty) {
          _leaderboard[i] = _leaderboard[i].copyWith(name: resolved);
        }
      }
    } catch (e) {
      debugPrint('Failed to enrich pushups leaderboard names: $e');
    }
  }

  Future<void> _computeLeaderboardFallback() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('assessments')
        .where('activityKey', isEqualTo: 'pushups')
        .orderBy('score', descending: true)
        .limit(200)
        .get();

    final Map<String, _LeaderboardItem> bestPerUser = {};
    for (final doc in snapshot.docs) {
      final d = doc.data();
      final uid = d['userId']?.toString() ?? doc.id;
      final score = (d['score'] is num) ? (d['score'] as num).toInt() : 0;
      final name = (d['displayName'] ?? 'Player').toString();
      if (!bestPerUser.containsKey(uid) || bestPerUser[uid]!.score < score) {
        bestPerUser[uid] = _LeaderboardItem(
          userId: uid,
          name: name,
          score: score,
          timestamp: d['timestamp'],
        );
      }
    }

    final list = bestPerUser.values.toList();
    list.sort((a, b) => b.score.compareTo(a.score));
    _leaderboard = list.take(_leaderboardLimit).toList();

    // Try to enrich names from users collection
    await _enrichNamesForLeaderboard();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final myBestAttemptQuery = await FirebaseFirestore.instance
          .collection('assessments')
          .where('userId', isEqualTo: user.uid)
          .where('activityKey', isEqualTo: 'pushups')
          .orderBy('score', descending: true)
          .limit(1)
          .get();
      if (myBestAttemptQuery.docs.isNotEmpty) {
        final myBest = (myBestAttemptQuery.docs.first.data()['score'] is num)
            ? (myBestAttemptQuery.docs.first.data()['score'] as num).toInt()
            : 0;
        final higherCount = bestPerUser.values
            .where((it) => it.score > myBest)
            .length;
        _myRank = higherCount + 1;
        _personalBest = myBest;
        _personalBestWhen = _formatTimestampCompact(
          myBestAttemptQuery.docs.first.data()['timestamp'],
        );
      } else {
        _myRank = null;
      }
    }
  }

  Future<void> _onRecordPressed() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PushUpRecordPage()),
    );
    if (result == true) {
      await _loadPersonalBestAndLeaderboard();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Result saved.')));
      }
    }
  }

  static String _formatTimestampCompact(dynamic ts) {
    try {
      if (ts == null) return '';
      if (ts is Timestamp) {
        final dt = ts.toDate();
        return '${dt.day}/${dt.month}/${dt.year}';
      }
      if (ts is int) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        return '${dt.day}/${dt.month}/${dt.year}';
      }
      if (ts is String) {
        final dt = DateTime.tryParse(ts);
        if (dt != null) return '${dt.day}/${dt.month}/${dt.year}';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Push-ups Test',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        elevation: 1,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // PROMINENT START BUTTON and personal best
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Personal Best',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _personalBest != null
                        ? '$_personalBest reps • $_personalBestWhen'
                        : 'No recorded attempts',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _onRecordPressed,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Place phone on a stable surface so your full body is visible.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Leaderboard
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: Colors.black,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Leaderboard — Push-ups',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    else if (_leaderboard.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'No leaderboard data yet',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: _leaderboard.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final item = _leaderboard[i];
                            final rank = i + 1;
                            final isMe = item.userId == user?.uid;
                            return Material(
                              color: isMe
                                  ? Colors.green[900]
                                  : Colors.grey[900],
                              borderRadius: BorderRadius.circular(10),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: _buildRankLeading(rank),
                                title: Text(
                                  item.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: Text(
                                  '${item.score} reps',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _myRank != null
                                ? 'Your rank: #$_myRank'
                                : 'Your rank: —',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton(
                          onPressed: _loadPersonalBestAndLeaderboard,
                          child: const Text(
                            'Reload',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // custom leading widget: medal for top 3, else rank number
  Widget _buildRankLeading(int rank) {
    const gold = Color(0xFFFFD700); // gold
    const silver = Color(0xFFC0C0C0); // silver
    const bronze = Color(0xFFCD7F32); // bronze

    if (rank == 1) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: gold,
        child: const Text(
          '1',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      );
    } else if (rank == 2) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: silver,
        child: const Text(
          '2',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      );
    } else if (rank == 3) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: bronze,
        child: const Text(
          '3',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.black,
        child: Text(
          rank.toString(),
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
  }
}

class _LeaderboardItem {
  final String userId;
  final String name;
  final int score;
  final dynamic timestamp;
  _LeaderboardItem({
    required this.userId,
    required this.name,
    required this.score,
    this.timestamp,
  });

  // helper to produce a new instance with updated fields (immutable-ish)
  _LeaderboardItem copyWith({
    String? userId,
    String? name,
    int? score,
    dynamic timestamp,
  }) {
    return _LeaderboardItem(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      score: score ?? this.score,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
