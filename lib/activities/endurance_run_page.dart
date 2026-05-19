// lib/activities/endurance_run_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'endurance_run_record_page.dart';

class EnduranceRunPage extends StatefulWidget {
  const EnduranceRunPage({super.key});

  @override
  State<EnduranceRunPage> createState() => _EnduranceRunPageState();
}

class _EnduranceRunPageState extends State<EnduranceRunPage> {
  bool _loading = true;
  String? _error;

  // leaderboard rows: Map with keys: userId, displayName, score, timestamp
  List<Map<String, dynamic>> _leaders = [];
  Map<String, dynamic>? _myBest;
  int? _myRank;

  // limits & tokens
  static const int _limit = 100;
  static const int _assessmentFetchLimit = 500;
  int _loadToken = 0;

  final String _activityKey = 'endurance_run';

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  /// Helper: enrich leader rows with names from users collection (non-fatal)
  Future<void> _enrichWithUserNames(List<Map<String, dynamic>> leaders) async {
    if (leaders.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final ids = leaders
        .map((e) => (e['userId'] ?? '').toString())
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
            final name = (data['name'] ?? '').toString();
            if (name.isNotEmpty) idToName[id] = name;
          }
        }
      }
      for (final row in leaders) {
        final uid = (row['userId'] ?? '').toString();
        if (uid.isEmpty) continue;
        final nameFromUsers = idToName[uid];
        if (nameFromUsers != null && nameFromUsers.isNotEmpty) {
          row['displayName'] = nameFromUsers;
        }
      }
    } catch (e) {
      debugPrint('Enrich names failed: $e');
    }
  }

  Future<void> _loadLeaderboard() async {
    final int token = ++_loadToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _leaders = [];
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

    try {
      final db = FirebaseFirestore.instance;

      // --- DEBUG: quick existence check (no orderBy)
      try {
        final rawSnap = await db
            .collection('best_scores')
            .where('activityKey', isEqualTo: _activityKey)
            .limit(5)
            .get();
        debugPrint('[DBG] best_scores raw count=${rawSnap.docs.length}');
        if (rawSnap.docs.isNotEmpty) {
          debugPrint(
            '[DBG] best_scores sample doc0=${rawSnap.docs.first.data()}',
          );
        } else {
          debugPrint('[DBG] best_scores: no docs returned by simple query');
        }
      } catch (e) {
        debugPrint('[DBG] best_scores simple query failed: $e');
      }

      // PRIMARY: try reading best_scores ordered ascending (lower is better for endurance)
      try {
        final bestRef = db.collection('best_scores');
        final topSnap = await bestRef
            .where('activityKey', isEqualTo: _activityKey)
            .orderBy('score')
            .limit(_limit)
            .get();

        debugPrint('[DBG] best_scores ordered count=${topSnap.docs.length}');
        if (topSnap.docs.isNotEmpty) {
          final List<Map<String, dynamic>> leaders = topSnap.docs.map((d) {
            final data = d.data();
            return {
              'userId': data['userId']?.toString() ?? d.id,
              'displayName': (data['displayName'] ?? 'Athlete').toString(),
              'score': (data['score'] is num)
                  ? data['score'] as num
                  : (num.tryParse(data['score']?.toString() ?? '')),
              'timestamp': data['timestamp'],
            };
          }).toList();

          await _enrichWithUserNames(leaders);

          // my best entry
          final mySnap = await bestRef
              .where('activityKey', isEqualTo: _activityKey)
              .where('userId', isEqualTo: uid)
              .limit(1)
              .get();
          final myBest = mySnap.docs.isNotEmpty
              ? mySnap.docs.first.data()
              : null;

          int? myRank;
          if (myBest != null) {
            final myScore = myBest['score'];
            final betterSnap = await bestRef
                .where('activityKey', isEqualTo: _activityKey)
                .where('score', isLessThan: myScore)
                .get();
            myRank = betterSnap.docs.length + 1;
          }

          if (!mounted || token != _loadToken) return;
          setState(() {
            _leaders = leaders.take(_limit).toList();
            _myBest = myBest;
            _myRank = myRank;
            _loading = false;
            _error = null;
          });
          return;
        } else {
          debugPrint(
            '[DBG] best_scores ordered returned 0 docs; falling back to assessments',
          );
        }
      } catch (e) {
        debugPrint('[DBG] best_scores ordered query failed: $e');
        // continue to fallback
      }

      // FALLBACK: try assessments (dedupe client-side)
      try {
        final assessmentsRef = db.collection('assessments');

        // debug: try a simple no-order query to see if docs exist
        try {
          final rawAssess = await assessmentsRef
              .where('activityKey', isEqualTo: _activityKey)
              .limit(5)
              .get();
          debugPrint('[DBG] assessments raw count=${rawAssess.docs.length}');
          if (rawAssess.docs.isNotEmpty) {
            debugPrint(
              '[DBG] assessments sample doc0=${rawAssess.docs.first.data()}',
            );
          }
        } catch (e) {
          debugPrint('[DBG] assessments simple query failed: $e');
        }

        final attemptsSnap = await assessmentsRef
            .where('activityKey', isEqualTo: _activityKey)
            .orderBy('score')
            .limit(_assessmentFetchLimit)
            .get();

        debugPrint(
          '[DBG] assessments ordered count=${attemptsSnap.docs.length}',
        );

        final Map<String, Map<String, dynamic>> bestPerUser = {};
        for (final doc in attemptsSnap.docs) {
          final d = doc.data();
          final userId = (d['userId'] ?? '').toString();
          if (userId.isEmpty) continue;

          num? scoreNum;
          final rawScore = d['score'];
          if (rawScore is num) {
            scoreNum = rawScore;
          } else if (rawScore != null)
            scoreNum = num.tryParse(rawScore.toString());

          final timestamp = d['timestamp'];

          if (!bestPerUser.containsKey(userId)) {
            bestPerUser[userId] = {
              'userId': userId,
              'displayName': d['displayName'] ?? userId,
              'score': scoreNum,
              'timestamp': timestamp,
            };
          } else {
            final existing = bestPerUser[userId]!;
            final existingScore = existing['score'] as num?;
            if (scoreNum != null &&
                (existingScore == null || scoreNum < existingScore)) {
              bestPerUser[userId] = {
                'userId': userId,
                'displayName': d['displayName'] ?? userId,
                'score': scoreNum,
                'timestamp': timestamp,
              };
            }
          }
        }

        final List<Map<String, dynamic>> uniqueLeaders =
            bestPerUser.values.toList()..sort((a, b) {
              final na = a['score'] as num?;
              final nb = b['score'] as num?;
              if (na == null && nb == null) return 0;
              if (na == null) return 1;
              if (nb == null) return -1;
              return na.compareTo(nb);
            });

        await _enrichWithUserNames(uniqueLeaders);

        final myBest = bestPerUser[uid];
        int? myRank;
        if (myBest != null) {
          final idx = uniqueLeaders.indexWhere((r) => r['userId'] == uid);
          myRank = idx >= 0 ? idx + 1 : null;
        }

        if (!mounted || token != _loadToken) return;
        setState(() {
          _leaders = uniqueLeaders.take(_limit).toList();
          _myBest = myBest;
          _myRank = myRank;
          _loading = false;
          _error = null;
        });
        return;
      } catch (e) {
        debugPrint('[DBG] assessments fallback failed: $e');
        rethrow;
      }
    } on FirebaseException catch (e) {
      debugPrint(
        'Firestore error loading endurance leaderboard: ${e.code} ${e.message}',
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'Firestore error: ${e.code} ${e.message}';
      });
    } catch (e, st) {
      debugPrint('Unexpected endurance leaderboard error: $e\n$st');
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'Unexpected error: $e';
      });
    }
  }

  String _niceName(Map<String, dynamic> row) {
    final n = row['displayName'];
    if (n == null || n.toString().trim().isEmpty) {
      return (row['userId'] ?? 'Athlete').toString();
    }
    return n.toString();
  }

  String _initials(String nameOrId) {
    final s = nameOrId.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _fmtTimestamp(dynamic ts) {
    try {
      if (ts == null) return '';
      if (ts is Timestamp) {
        final d = ts.toDate();
        return '${d.day}/${d.month}/${d.year}';
      }
      if (ts is int) {
        final d = DateTime.fromMillisecondsSinceEpoch(ts);
        return '${d.day}/${d.month}/${d.year}';
      }
      return ts.toString().split(' ').first;
    } catch (_) {
      return '';
    }
  }

  Widget _medal(Color bg, String text) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: bg.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderTile(
    Map<String, dynamic> row,
    int index,
    String currentUid,
  ) {
    final rank = index + 1;
    final isMe = currentUid == (row['userId'] ?? '');
    final display = _niceName(row);
    final score = row['score'];
    final timestamp = _fmtTimestamp(row['timestamp']);

    Widget? medal;
    if (rank == 1) {
      medal = _medal(Colors.amber, '1');
    } else if (rank == 2)
      medal = _medal(Colors.grey.shade400, '2');
    else if (rank == 3)
      medal = _medal(Colors.brown.shade400, '3');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Center(
                    child:
                        medal ??
                        Text(
                          '$rank',
                          style: TextStyle(
                            color: isMe ? Colors.amber : Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                  ),
                ),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isMe
                      ? Colors.amber
                      : const Color(0xFF123041),
                  child: Text(
                    _initials(display),
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
                        display,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.white70,
                          fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            timestamp,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          if (row['timestamp'] != null &&
                              row['timestamp'] is Timestamp) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ENDURANCE',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      score != null
                          ? _formatTime(
                              (score is num)
                                  ? score.toInt()
                                  : int.parse(score.toString()),
                            )
                          : '—',
                      style: TextStyle(
                        color: isMe ? Colors.amber : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '1.6 km',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onRecordPressed() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EnduranceRunRecordPage()),
    );
    if (result == true) {
      await _loadLeaderboard();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Result saved.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final personalBestText = _myBest != null
        ? (_myBest!['score'] != null
              ? '${_formatTime((_myBest!['score'] is num) ? _myBest!['score'].toInt() : int.parse(_myBest!['score'].toString()))} • ${_fmtTimestamp(_myBest!['timestamp'])}'
              : '')
        : 'No recorded attempts';

    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071018),
        elevation: 0,
        title: const Text(
          'Endurance Run (1.6 km)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            onPressed: _loadLeaderboard,
            icon: const Icon(Icons.refresh),
            color: Colors.white,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadLeaderboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // Personal best card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F2933), Color(0xFF071018)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer, color: Colors.white70),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Your Personal Best',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _onRecordPressed,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Start Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
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
                    const SizedBox(height: 8),
                    const Text(
                      'Place phone so athlete and track are visible for the full 1.6 km run.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: const [
                  Expanded(
                    child: Text(
                      'Leaderboard — Endurance Run (1.6 km)',
                      style: TextStyle(
                        color: Colors.white70,
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

            if (!_loading && _leaders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _error ?? 'No leaderboard data yet',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ),

            ..._leaders.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              return _buildLeaderTile(row, idx, uid);
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
                    onPressed: _loadLeaderboard,
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

  static String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }
}
