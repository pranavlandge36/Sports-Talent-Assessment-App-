// lib/activities/situps_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Replace with situp recorder if available; reusing pushups recorder as default.
import 'situp_record_page.dart';

class SitUpsPage extends StatefulWidget {
  const SitUpsPage({super.key});

  @override
  State<SitUpsPage> createState() => _SitUpsPageState();
}

class _SitUpsPageState extends State<SitUpsPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _leaders =
      []; // userId, displayName, score (int seconds or reps), timestamp
  Map<String, dynamic>? _myBest;
  int? _myRank;

  static const int _limit = 100;
  static const int _assessmentFetchLimit = 500;
  final String _activityKey = 'situps';
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  /// parse score to int (reps or seconds). supports numeric, "mm:ss", "m:ss", or integer strings.
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

  Future<void> _enrichNames(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final ids = rows
        .map((r) => (r['userId'] ?? '').toString())
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
      for (final row in rows) {
        final uid = (row['userId'] ?? '').toString();
        if (uid.isEmpty) continue;
        final resolved = idToName[uid];
        if (resolved != null && resolved.isNotEmpty) {
          row['displayName'] = resolved;
        }
        // fallback: if no displayName set, keep existing or fill with email/userId later in UI
      }
    } catch (e) {
      debugPrint('Failed to enrich names: $e');
    }
  }

  List<Map<String, dynamic>> _dedupeAndSortDesc(
    Map<String, Map<String, dynamic>> map,
  ) {
    final list = map.values.toList();
    list.sort((a, b) {
      final na = a['score'] as num?;
      final nb = b['score'] as num?;
      if (na == null && nb == null) return 0;
      if (na == null) return 1;
      if (nb == null) return -1;
      return nb.compareTo(na); // descending (higher is better)
    });
    return list;
  }

  Future<void> _loadLeaderboard() async {
    final token = ++_loadToken;
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

    final db = FirebaseFirestore.instance;

    // 1) Primary: try best_scores ordered desc
    try {
      // debug existence
      try {
        final sample = await db
            .collection('best_scores')
            .where('activityKey', isEqualTo: _activityKey)
            .limit(1)
            .get();
        debugPrint('[DBG] best_scores existence=${sample.docs.length}');
        if (sample.docs.isNotEmpty) {
          debugPrint('[DBG] best_scores sample=${sample.docs.first.data()}');
        }
      } catch (e) {
        debugPrint('[DBG] best_scores existence check failed: $e');
      }

      try {
        final topSnap = await db
            .collection('best_scores')
            .where('activityKey', isEqualTo: _activityKey)
            .orderBy('score', descending: true)
            .limit(_limit)
            .get();
        debugPrint('[DBG] best_scores ordered count=${topSnap.docs.length}');
        if (topSnap.docs.isNotEmpty) {
          final rows = topSnap.docs.map((d) {
            final data = d.data();
            return {
              'userId': data['userId']?.toString() ?? d.id,
              'displayName': (data['displayName'] ?? '').toString(),
              'score': _parseScore(data['score']),
              'timestamp': data['timestamp'],
            };
          }).toList();

          await _enrichNames(rows);

          final mySnap = await db
              .collection('best_scores')
              .where('activityKey', isEqualTo: _activityKey)
              .where('userId', isEqualTo: uid)
              .limit(1)
              .get();
          final myBest = mySnap.docs.isNotEmpty
              ? mySnap.docs.first.data()
              : null;
          int? myRank;
          if (myBest != null) {
            final myScore = _parseScore(myBest['score']);
            if (myScore != null) {
              final betterSnap = await db
                  .collection('best_scores')
                  .where('activityKey', isEqualTo: _activityKey)
                  .where('score', isGreaterThan: myScore)
                  .get();
              myRank = betterSnap.docs.length + 1;
            }
          }

          if (!mounted || token != _loadToken) return;
          setState(() {
            _leaders = rows.take(_limit).toList();
            _myBest = myBest;
            _myRank = myRank;
            _loading = false;
            _error = null;
          });
          return;
        } else {
          debugPrint(
            '[DBG] best_scores ordered returned 0 docs; falling back.',
          );
        }
      } catch (e) {
        debugPrint('[DBG] best_scores ordered query failed: $e');
        // fall through
      }
    } catch (e) {
      debugPrint('Primary best_scores attempt failed: $e');
    }

    // 2) Fallback: assessments ordered (may require index)
    try {
      // debug existence
      try {
        final raw = await db
            .collection('assessments')
            .where('activityKey', isEqualTo: _activityKey)
            .limit(1)
            .get();
        debugPrint('[DBG] assessments existence=${raw.docs.length}');
        if (raw.docs.isNotEmpty) {
          debugPrint('[DBG] assessments sample=${raw.docs.first.data()}');
        }
      } catch (e) {
        debugPrint('[DBG] assessments existence check failed: $e');
      }

      try {
        final attemptsSnap = await db
            .collection('assessments')
            .where('activityKey', isEqualTo: _activityKey)
            .orderBy('score', descending: true)
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
          final scoreNum = _parseScore(d['score']);
          final ts = d['timestamp'];
          if (!bestPerUser.containsKey(userId)) {
            bestPerUser[userId] = {
              'userId': userId,
              'displayName': (d['displayName'] ?? '').toString(),
              'score': scoreNum,
              'timestamp': ts,
            };
          } else {
            final existing = bestPerUser[userId]!;
            final existingScore = existing['score'] as int?;
            if (scoreNum != null &&
                (existingScore == null || scoreNum > existingScore)) {
              bestPerUser[userId] = {
                'userId': userId,
                'displayName': (d['displayName'] ?? '').toString(),
                'score': scoreNum,
                'timestamp': ts,
              };
            }
          }
        }

        final unique = _dedupeAndSortDesc(bestPerUser);
        await _enrichNames(unique);

        final myBest = bestPerUser[uid];
        int? myRank;
        if (myBest != null) {
          final idx = unique.indexWhere((r) => r['userId'] == uid);
          myRank = idx >= 0 ? idx + 1 : null;
        }

        if (!mounted || token != _loadToken) return;
        setState(() {
          _leaders = unique.take(_limit).toList();
          _myBest = myBest;
          _myRank = myRank;
          _loading = false;
          _error = null;
        });
        return;
      } catch (e) {
        debugPrint('[DBG] assessments ordered query failed (likely index): $e');
        // fall through to unordered fallback
      }
    } catch (e) {
      debugPrint('Assessments attempt failed: $e');
    }

    // 3) Final fallback: unordered fetch + client-side dedupe/sort
    try {
      // try best_scores unordered first
      try {
        final raw = await db
            .collection('best_scores')
            .where('activityKey', isEqualTo: _activityKey)
            .limit(_assessmentFetchLimit)
            .get();
        debugPrint('[DBG] best_scores unordered count=${raw.docs.length}');
        if (raw.docs.isNotEmpty) {
          final Map<String, Map<String, dynamic>> bestPerUser = {};
          for (final d in raw.docs) {
            final data = d.data();
            final uidDoc = data['userId']?.toString() ?? d.id;
            final scoreNum = _parseScore(data['score']);
            final ts = data['timestamp'];
            if (!bestPerUser.containsKey(uidDoc)) {
              bestPerUser[uidDoc] = {
                'userId': uidDoc,
                'displayName': (data['displayName'] ?? '').toString(),
                'score': scoreNum,
                'timestamp': ts,
              };
            } else {
              final existing = bestPerUser[uidDoc]!;
              final existingScore = existing['score'] as int?;
              if (scoreNum != null &&
                  (existingScore == null || scoreNum > existingScore)) {
                bestPerUser[uidDoc] = {
                  'userId': uidDoc,
                  'displayName': (data['displayName'] ?? '').toString(),
                  'score': scoreNum,
                  'timestamp': ts,
                };
              }
            }
          }

          final uniqueLeaders = _dedupeAndSortDesc(bestPerUser);
          await _enrichNames(uniqueLeaders);

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
      debugPrint('[DBG] assessments unordered count=${rawAssess.docs.length}');

      final Map<String, Map<String, dynamic>> bestPerUser = {};
      for (final doc in rawAssess.docs) {
        final d = doc.data();
        final uidDoc = (d['userId'] ?? '').toString();
        if (uidDoc.isEmpty) continue;
        final scoreNum = _parseScore(d['score']);
        final ts = d['timestamp'];
        if (!bestPerUser.containsKey(uidDoc)) {
          bestPerUser[uidDoc] = {
            'userId': uidDoc,
            'displayName': (d['displayName'] ?? '').toString(),
            'score': scoreNum,
            'timestamp': ts,
          };
        } else {
          final existing = bestPerUser[uidDoc]!;
          final existingScore = existing['score'] as int?;
          if (scoreNum != null &&
              (existingScore == null || scoreNum > existingScore)) {
            bestPerUser[uidDoc] = {
              'userId': uidDoc,
              'displayName': (d['displayName'] ?? '').toString(),
              'score': scoreNum,
              'timestamp': ts,
            };
          }
        }
      }

      final uniqueLeaders = _dedupeAndSortDesc(bestPerUser);
      await _enrichNames(uniqueLeaders);

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
    } on FirebaseException catch (e) {
      debugPrint(
        'Firestore error loading situps leaderboard: ${e.code} ${e.message}',
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'Firestore error: ${e.code} ${e.message}';
      });
    } catch (e, st) {
      debugPrint('Unexpected situps leaderboard error: $e\n$st');
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
      // fallback to email (if present in row) or userId
      final email = row['email']?.toString();
      if (email != null && email.isNotEmpty) return email;
      return (row['userId'] ?? 'Athlete').toString();
    }
    return n.toString();
  }

  String _fmtTs(dynamic ts) {
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
      final parsed = DateTime.tryParse(ts.toString());
      if (parsed != null) return '${parsed.day}/${parsed.month}/${parsed.year}';
      return ts.toString().split(' ').first;
    } catch (_) {
      return '';
    }
  }

  Widget _medal(Color bg, String text) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTile(Map<String, dynamic> row, int index, String currentUid) {
    final rank = index + 1;
    final isMe = currentUid == (row['userId'] ?? '');
    final display = _niceName(row);
    final score = row['score'];
    final ts = _fmtTs(row['timestamp']);

    Widget? medalWidget;
    if (rank == 1) {
      medalWidget = _medal(const Color(0xFFFFD700), '1');
    } else if (rank == 2)
      medalWidget = _medal(const Color(0xFFC0C0C0), '2');
    else if (rank == 3)
      medalWidget = _medal(const Color(0xFFCD7F32), '3');

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
                        medalWidget ??
                        Text(
                          '$rank',
                          style: TextStyle(
                            color: isMe ? Colors.amber : Colors.white70,
                            fontWeight: FontWeight.w700,
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ts,
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
                      score != null ? score.toString() : '—',
                      style: TextStyle(
                        color: isMe ? Colors.amber : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'reps',
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

  String _initials(String s) {
    final v = s.trim();
    if (v.isEmpty) return '?';
    final parts = v.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _onRecordPressed() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SitUpRecordPage()),
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
              ? '${_myBest!['score']} reps • ${_fmtTs(_myBest!['timestamp'])}'
              : '')
        : 'No recorded attempts';

    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071018),
        elevation: 0,
        title: const Text(
          'Sit-ups Test',
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
                        const Icon(Icons.fitness_center, color: Colors.white70),
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
                      'Place phone so athlete and mat are visible for the full test.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: const [
                  Expanded(
                    child: Text(
                      'Leaderboard — Sit-ups',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Reps',
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
            ..._leaders.asMap().entries.map((e) {
              final idx = e.key;
              final row = e.value;
              return _buildTile(row, idx, uid);
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
}
