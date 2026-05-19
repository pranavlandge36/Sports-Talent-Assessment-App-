// lib/activities/shuttle_run_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'shuttle_run_record_page.dart';

class ShuttleRunPage extends StatefulWidget {
  const ShuttleRunPage({super.key});

  @override
  State<ShuttleRunPage> createState() => _ShuttleRunPageState();
}

class _ShuttleRunPageState extends State<ShuttleRunPage> {
  int? _personalBestSeconds;
  String _personalBestWhen = '';
  List<_LeaderboardItem> _leaderboard = [];
  Map<String, dynamic>? _myBest;
  int? _myRank;
  bool _loading = true;
  String? _error;

  final int _leaderboardLimit = 10;
  static const int _limit = 100;
  static const int _assessmentFetchLimit = 500;
  final String _activityKey = 'shuttle_run';
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadPersonalBestAndLeaderboard();
  }

  Future<void> _enrichNamesForLeaderboard(List<_LeaderboardItem> rows) async {
    if (rows.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final ids = rows
        .map((r) => r.userId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
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
            final name = (data['name'] ?? data['displayName'] ?? '').toString();
            if (name.isNotEmpty) idToName[id] = name;
          }
        }
      }
      for (var i = 0; i < rows.length; i++) {
        final resolved = idToName[rows[i].userId];
        if (resolved != null && resolved.isNotEmpty) {
          rows[i] = rows[i].copyWith(name: resolved);
        }
      }
    } catch (e) {
      debugPrint('Failed to enrich shuttle_run names: $e');
    }
  }

  int? _parseScore(dynamic raw) {
    try {
      if (raw == null) return null;
      if (raw is num) return raw.toInt();
      final s = raw.toString();
      final n = int.tryParse(s);
      if (n != null) return n;
      if (s.contains(':')) {
        final parts = s.split(':').map((p) => int.tryParse(p) ?? 0).toList();
        if (parts.length == 2) return parts[0] * 60 + parts[1];
        if (parts.length == 3) {
          return parts[0] * 3600 + parts[1] * 60 + parts[2];
        }
      }
      final d = double.tryParse(s);
      if (d != null) return d.round();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPersonalBestAndLeaderboard() async {
    final token = ++_loadToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _leaderboard = [];
        _myBest = null;
        _myRank = null;
      });
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted && token == _loadToken) {
        setState(() {
          _loading = false;
          _error = 'Not authenticated';
        });
      }
      return;
    }

    final db = FirebaseFirestore.instance;
    bool done = false;

    try {
      // personal best from best_scores doc
      try {
        final bestDoc = await db
            .collection('best_scores')
            .doc('${uid}_shuttle_run')
            .get();
        if (bestDoc.exists) {
          final data = bestDoc.data()!;
          _personalBestSeconds = (data['score'] is num)
              ? (data['score'] as num).toInt()
              : _parseScore(data['score']);
          _personalBestWhen = _formatTimestampCompact(data['timestamp']);
        } else {
          // fallback: best attempt (lowest time)
          final q = await db
              .collection('assessments')
              .where('userId', isEqualTo: uid)
              .where('activityKey', isEqualTo: _activityKey)
              .orderBy('score')
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final d = q.docs.first.data();
            _personalBestSeconds = (d['score'] is num)
                ? (d['score'] as num).toInt()
                : _parseScore(d['score']);
            _personalBestWhen = _formatTimestampCompact(d['timestamp']);
          } else {
            _personalBestSeconds = null;
            _personalBestWhen = '';
          }
        }
      } catch (e) {
        debugPrint('Personal best check failed: $e');
      }

      // PRIMARY: best_scores ordered ascending (lower better)
      try {
        final topSnap = await db
            .collection('best_scores')
            .where('activityKey', isEqualTo: _activityKey)
            .orderBy('score')
            .limit(_limit)
            .get();
        debugPrint(
          '[DBG] shuttle best_scores ordered count=${topSnap.docs.length}',
        );
        if (topSnap.docs.isNotEmpty) {
          final rows = topSnap.docs.map((doc) {
            final d = doc.data();
            return _LeaderboardItem(
              userId: (d['userId'] ?? doc.id).toString(),
              name: (d['displayName'] ?? '').toString(),
              score: (d['score'] is num)
                  ? (d['score'] as num).toInt()
                  : (_parseScore(d['score']) ?? 0),
              timestamp: d['timestamp'],
              email: (d['email'] ?? '').toString(),
            );
          }).toList();

          await _enrichNamesForLeaderboard(rows);

          final mySnap = await db
              .collection('best_scores')
              .where('activityKey', isEqualTo: _activityKey)
              .where('userId', isEqualTo: uid)
              .limit(1)
              .get();
          _myBest = mySnap.docs.isNotEmpty ? mySnap.docs.first.data() : null;

          int? myRank;
          if (_myBest != null) {
            final myScore = _parseScore(_myBest!['score']);
            if (myScore != null) {
              final faster = await db
                  .collection('best_scores')
                  .where('activityKey', isEqualTo: _activityKey)
                  .where('score', isLessThan: myScore)
                  .get();
              myRank = faster.docs.length + 1;
            }
          }

          if (!mounted || token != _loadToken) return;
          setState(() {
            _leaderboard = rows.take(_leaderboardLimit).toList();
            _myRank = myRank;
            _loading = false;
            _error = null;
          });
          done = true;
        } else {
          debugPrint('[DBG] best_scores ordered empty; will fallback.');
        }
      } catch (e) {
        debugPrint('[DBG] best_scores ordered query failed: $e');
      }
    } catch (e) {
      debugPrint('Primary best_scores attempt failed: $e');
    }

    if (done) return;

    // SECONDARY: assessments ordered (may require index)
    try {
      try {
        final attemptsSnap = await db
            .collection('assessments')
            .where('activityKey', isEqualTo: _activityKey)
            .orderBy('score')
            .limit(_assessmentFetchLimit)
            .get();
        debugPrint(
          '[DBG] shuttle assessments ordered count=${attemptsSnap.docs.length}',
        );

        final Map<String, _LeaderboardItem> bestPerUser = {};
        for (final doc in attemptsSnap.docs) {
          final d = doc.data();
          final uidDoc = (d['userId'] ?? '').toString();
          if (uidDoc.isEmpty) continue;
          final sc = (d['score'] is num)
              ? (d['score'] as num).toInt()
              : (_parseScore(d['score']) ?? 0);
          final name = (d['displayName'] ?? '').toString();
          if (!bestPerUser.containsKey(uidDoc) ||
              bestPerUser[uidDoc]!.score > sc) {
            bestPerUser[uidDoc] = _LeaderboardItem(
              userId: uidDoc,
              name: name,
              score: sc,
              timestamp: d['timestamp'],
              email: (d['email'] ?? '').toString(),
            );
          }
        }

        final list = bestPerUser.values.toList()
          ..sort((a, b) => a.score.compareTo(b.score)); // ascending
        await _enrichNamesForLeaderboard(list);

        final myBest = bestPerUser[uid];
        int? myRank;
        if (myBest != null) {
          final idx = list.indexWhere((r) => r.userId == uid);
          myRank = idx >= 0 ? idx + 1 : null;
        }

        if (!mounted || token != _loadToken) return;
        setState(() {
          _leaderboard = list.take(_leaderboardLimit).toList();
          _myBest = myBest != null
              ? {'score': myBest.score, 'timestamp': myBest.timestamp}
              : null;
          _myRank = myRank;
          _loading = false;
          _error = null;
        });
        done = true;
      } catch (e) {
        debugPrint('[DBG] assessments ordered failed (index?): $e');
      }
    } catch (e) {
      debugPrint('Assessments ordered attempt failed: $e');
    }

    if (done) return;

    // FINAL FALLBACK: unordered fetch + client-side dedupe/sort
    try {
      // try best_scores unordered
      try {
        final raw = await db
            .collection('best_scores')
            .where('activityKey', isEqualTo: _activityKey)
            .limit(_assessmentFetchLimit)
            .get();
        debugPrint(
          '[DBG] shuttle best_scores unordered count=${raw.docs.length}',
        );
        if (raw.docs.isNotEmpty) {
          final Map<String, _LeaderboardItem> bestPerUser = {};
          for (final d in raw.docs) {
            final data = d.data();
            final uidDoc = data['userId']?.toString() ?? d.id;
            final sc = (data['score'] is num)
                ? (data['score'] as num).toInt()
                : (_parseScore(data['score']) ?? 0);
            final name = (data['displayName'] ?? '').toString();
            final ts = data['timestamp'];
            final email = (data['email'] ?? '').toString();
            if (!bestPerUser.containsKey(uidDoc) ||
                bestPerUser[uidDoc]!.score > sc) {
              bestPerUser[uidDoc] = _LeaderboardItem(
                userId: uidDoc,
                name: name,
                score: sc,
                timestamp: ts,
                email: email,
              );
            }
          }
          final list = bestPerUser.values.toList()
            ..sort((a, b) => a.score.compareTo(b.score));
          await _enrichNamesForLeaderboard(list);

          final myBest = bestPerUser[uid];
          int? myRank;
          if (myBest != null) {
            final idx = list.indexWhere((r) => r.userId == uid);
            myRank = idx >= 0 ? idx + 1 : null;
          }

          if (!mounted || token != _loadToken) return;
          setState(() {
            _leaderboard = list.take(_leaderboardLimit).toList();
            _myBest = myBest != null
                ? {'score': myBest.score, 'timestamp': myBest.timestamp}
                : null;
            _myRank = myRank;
            _loading = false;
            _error = null;
          });
          return;
        } else {
          debugPrint(
            '[DBG] best_scores unordered empty; trying assessments unordered.',
          );
        }
      } catch (e) {
        debugPrint('[DBG] best_scores unordered failed: $e');
      }

      // assessments unordered
      final rawAssess = await db
          .collection('assessments')
          .where('activityKey', isEqualTo: _activityKey)
          .limit(_assessmentFetchLimit)
          .get();
      debugPrint(
        '[DBG] shuttle assessments unordered count=${rawAssess.docs.length}',
      );

      final Map<String, _LeaderboardItem> bestPerUser = {};
      for (final doc in rawAssess.docs) {
        final d = doc.data();
        final uidDoc = (d['userId'] ?? '').toString();
        if (uidDoc.isEmpty) continue;
        final sc = (d['score'] is num)
            ? (d['score'] as num).toInt()
            : (_parseScore(d['score']) ?? 0);
        final name = (d['displayName'] ?? '').toString();
        final ts = d['timestamp'];
        final email = (d['email'] ?? '').toString();
        if (!bestPerUser.containsKey(uidDoc) ||
            bestPerUser[uidDoc]!.score > sc) {
          bestPerUser[uidDoc] = _LeaderboardItem(
            userId: uidDoc,
            name: name,
            score: sc,
            timestamp: ts,
            email: email,
          );
        }
      }

      final list = bestPerUser.values.toList()
        ..sort((a, b) => a.score.compareTo(b.score));
      await _enrichNamesForLeaderboard(list);

      final myBest = bestPerUser[uid];
      int? myRank;
      if (myBest != null) {
        final idx = list.indexWhere((r) => r.userId == uid);
        myRank = idx >= 0 ? idx + 1 : null;
      }

      if (!mounted || token != _loadToken) return;
      setState(() {
        _leaderboard = list.take(_leaderboardLimit).toList();
        _myBest = myBest != null
            ? {'score': myBest.score, 'timestamp': myBest.timestamp}
            : null;
        _myRank = myRank;
        _loading = false;
        _error = null;
      });
    } on FirebaseException catch (e) {
      debugPrint(
        'Firestore error loading shuttle leaderboard: ${e.code} ${e.message}',
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'Firestore error: ${e.code} ${e.message}';
      });
    } catch (e, st) {
      debugPrint('Unexpected shuttle leaderboard error: $e\n$st');
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'Unexpected error: $e';
      });
    }
  }

  Future<void> _onRecordPressed() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ShuttleRunRecordPage()),
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

  String _labelForRow(_LeaderboardItem row) {
    final n = (row.name ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final email = (row.email ?? '').toString();
    if (email.isNotEmpty) {
      // nice fallback: use the part before @ if it's an email
      final parts = email.split('@');
      if (parts.isNotEmpty && parts.first.isNotEmpty) {
        final username = parts.first;
        // Capitalize first letter
        return username[0].toUpperCase() + username.substring(1);
      }
      return email;
    }
    return row.userId;
  }

  Widget _buildRankLeading(int rank) {
    const gold = Color(0xFFFFD700);
    const silver = Color(0xFFC0C0C0);
    const bronze = Color(0xFFCD7F32);

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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final personalBestText = _myBest != null
        ? (_myBest!['score'] != null
              ? '${_formatTime((_myBest!['score'] is num) ? _myBest!['score'] as int : _parseScore(_myBest!['score']) ?? 0)} • ${_formatTimestampCompact(_myBest!['timestamp'])}'
              : '')
        : (_personalBestSeconds != null
              ? '${_formatTime(_personalBestSeconds!)} • $_personalBestWhen'
              : 'No recorded attempts');

    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      appBar: AppBar(
        title: const Text(
          'Shuttle Run (5-10-5)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF071018),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadPersonalBestAndLeaderboard,
            icon: const Icon(Icons.refresh),
            color: Colors.white,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPersonalBestAndLeaderboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
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
                    personalBestText,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 18,
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
                    'Place phone on stable surface. Run the 5-10-5 course fully visible to camera.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: const [
                  Expanded(
                    child: Text(
                      'Leaderboard — Shuttle Run',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Time',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            if (!_loading && _error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            if (!_loading && _leaderboard.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _error ?? 'No leaderboard data yet',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            ..._leaderboard.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final rank = idx + 1;
              final isMe = item.userId == user?.uid;
              final label = _labelForRow(item);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Material(
                  color: isMe ? Colors.white10 : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: isMe
                            ? null
                            : const LinearGradient(
                                colors: [Color(0xFF0D1A22), Color(0xFF071018)],
                              ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Center(child: _buildRankLeading(rank)),
                          ),
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: isMe
                                ? Colors.amber
                                : const Color(0xFF123041),
                            child: Text(
                              _initials(label),
                              style: TextStyle(
                                color: isMe ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.white70,
                                    fontWeight: isMe
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTimestampCompact(item.timestamp),
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatTime(item.score),
                                style: TextStyle(
                                  color: isMe ? Colors.amber : Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '5-10-5',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _myRank != null ? 'Your rank: #$_myRank' : 'Your rank: —',
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
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _initials(String nameOrId) {
    final s = nameOrId.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }
}

class _LeaderboardItem {
  final String userId;
  final String? name;
  final int score; // seconds
  final dynamic timestamp;
  final String? email;

  _LeaderboardItem({
    required this.userId,
    this.name,
    required this.score,
    this.timestamp,
    this.email,
  });

  _LeaderboardItem copyWith({
    String? userId,
    String? name,
    int? score,
    dynamic timestamp,
    String? email,
  }) {
    return _LeaderboardItem(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      score: score ?? this.score,
      timestamp: timestamp ?? this.timestamp,
      email: email ?? this.email,
    );
  }
}
