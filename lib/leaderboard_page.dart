// lib/leaderboard_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final List<String> _activities = [
    'pushups',
    'situps',
    'vertical_jump',
    'shuttle_run',
    'endurance_run',
  ];

  String _selectedActivity = 'pushups';
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> _leaders = [];
  int? _myRank;
  Map<String, dynamic>? _myBest;

  // number of rows to show in UI
  static const int _limit = 100;

  // when querying raw assessments, fetch this many attempts to dedupe client-side.
  // Increase only if needed; larger number => more read costs.
  static const int _assessmentFetchLimit = 500;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  // Helper: fetch user names for the list of leader rows and update them in-place
  // THIS VERSION READS users/{uid}.name (requires your rules to allow read for authenticated users)
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
      final snaps = await Future.wait(
        ids.map((id) => db.collection('users').doc(id).get()),
      );

      final Map<String, String> idToName = {};
      for (int i = 0; i < ids.length; i++) {
        final snap = snaps[i];
        final id = ids[i];
        if (snap.exists) {
          final data = snap.data();
          final name = (data?['name'] ?? '').toString().trim();
          if (name.isNotEmpty) idToName[id] = name;
        }
      }

      for (final row in leaders) {
        final uid = (row['userId'] ?? '').toString();
        final nameFromUsers = idToName[uid];
        if (nameFromUsers != null && nameFromUsers.isNotEmpty) {
          row['displayName'] = nameFromUsers;
        }
      }
    } catch (e) {
      debugPrint('Failed to enrich leader names from users/: $e');
      // leave existing displayName fallback intact
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _loading = true;
      _error = null;
      _leaders = [];
      _myRank = null;
      _myBest = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not authenticated';
      });
      return;
    }

    try {
      final db = FirebaseFirestore.instance;

      // PRIMARY: try reading a sanitized 'best_scores' collection if you maintain one.
      try {
        final bestScoresRef = db.collection('best_scores');
        final topSnap = await bestScoresRef
            .where('activityKey', isEqualTo: _selectedActivity)
            .orderBy('score', descending: true)
            .limit(_limit)
            .get();

        // Use best_scores results if available (even if empty)
        if (topSnap.docs.isNotEmpty) {
          _leaders = topSnap.docs.map((d) {
            final data = d.data();
            return {
              'userId': data['userId'],
              'displayName': data['displayName'] ?? 'Athlete',
              'score': data['score'],
              'timestamp': data['timestamp'],
            };
          }).toList();

          // Enrich display names from users collection
          await _enrichWithUserNames(_leaders);

          // my best entry from best_scores
          final mySnap = await bestScoresRef
              .where('activityKey', isEqualTo: _selectedActivity)
              .where('userId', isEqualTo: uid)
              .limit(1)
              .get();

          _myBest = mySnap.docs.isNotEmpty ? mySnap.docs.first.data() : null;
          if (_myBest != null) {
            final myScore = _myBest!['score'];
            final higherSnap = await bestScoresRef
                .where('activityKey', isEqualTo: _selectedActivity)
                .where('score', isGreaterThan: myScore)
                .get();
            _myRank = higherSnap.docs.length + 1;
          } else {
            _myRank = null;
          }

          setState(() {
            _loading = false;
          });
          return;
        }
      } catch (e) {
        debugPrint(
          'best_scores read failed or empty, falling back to assessments: $e',
        );
      }

      // FALLBACK: Query top attempts from top-level `assessments` collection.
      final assessmentsRef = db.collection('assessments');
      final attemptsSnap = await assessmentsRef
          .where('activityKey', isEqualTo: _selectedActivity)
          .orderBy('score', descending: true)
          .limit(_assessmentFetchLimit)
          .get();

      // Deduplicate per user keeping the highest score seen in the fetched attempts.
      final Map<String, Map<String, dynamic>> bestPerUser = {};
      for (final doc in attemptsSnap.docs) {
        final d = doc.data();
        final userId = (d['userId'] ?? '').toString();
        if (userId.isEmpty) continue;

        final num? scoreNum = (d['score'] is num)
            ? d['score'] as num
            : (num.tryParse(d['score']?.toString() ?? ''));

        if (!bestPerUser.containsKey(userId)) {
          bestPerUser[userId] = {
            'userId': userId,
            'displayName': d['displayName'] ?? userId,
            'score': scoreNum,
            'timestamp': d['timestamp'],
          };
        } else {
          final existing = bestPerUser[userId]!;
          final existingScore = existing['score'] as num?;
          if (scoreNum != null &&
              (existingScore == null || scoreNum > existingScore)) {
            bestPerUser[userId] = {
              'userId': userId,
              'displayName': d['displayName'] ?? userId,
              'score': scoreNum,
              'timestamp': d['timestamp'],
            };
          }
        }
      }

      // Convert to list and sort descending by score
      final List<Map<String, dynamic>> uniqueLeaders =
          bestPerUser.values.toList()..sort((a, b) {
            final na = a['score'] as num?;
            final nb = b['score'] as num?;
            if (na == null && nb == null) return 0;
            if (na == null) return 1;
            if (nb == null) return -1;
            return nb.compareTo(na);
          });

      // Enrich with names from users collection
      await _enrichWithUserNames(uniqueLeaders);

      // find my best and rank among deduped list
      _myBest = bestPerUser[uid];
      if (_myBest != null) {
        final idx = uniqueLeaders.indexWhere((r) => r['userId'] == uid);
        _myRank = idx >= 0 ? idx + 1 : null;
      } else {
        _myRank = null;
      }

      // Limit visible leaderboard
      _leaders = uniqueLeaders.take(_limit).toList();

      setState(() {
        _loading = false;
      });
    } on FirebaseException catch (e) {
      debugPrint('Firestore error loading leaderboard: ${e.code} ${e.message}');
      setState(() {
        _loading = false;
        _error = e.code == 'permission-denied'
            ? 'Permission denied. Ensure leaderboard rules allow reads (assessments or best_scores).'
            : 'Failed to load leaderboard: ${e.message ?? e.code}';
      });
    } catch (e, st) {
      debugPrint('Unexpected leaderboard error: $e\n$st');
      setState(() {
        _loading = false;
        _error = 'Unexpected error loading leaderboard';
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
      // attempt parse if string
      return ts.toString().split(' ').first;
    } catch (_) {
      return '';
    }
  }

  Widget _buildLeaderTile(
    Map<String, dynamic> row,
    int index,
    String currentUid,
  ) {
    final rank = index + 1;
    final isMe = currentUid == (row['userId'] ?? '');
    final display = _niceName(row);
    final score = row['score'] ?? '—';
    final timestamp = _fmtTimestamp(row['timestamp']);

    // Medal for top 3
    Widget? medal;
    if (rank == 1) {
      medal = _medal(Colors.amber, '1');
    } else if (rank == 2) {
      medal = _medal(Colors.grey.shade400, '2');
    } else if (rank == 3) {
      medal = _medal(Colors.brown.shade400, '3');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: isMe ? Colors.white10 : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Optional: show detailed profile / stats
          },
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
                // Rank / medal
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

                // Avatar
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

                // Name + meta
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
                                _selectedActivity
                                    .replaceAll('_', ' ')
                                    .toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white54,
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

                // Score
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      score.toString(),
                      style: TextStyle(
                        color: isMe ? Colors.amber : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // unit hint
                      _unitForActivity(_selectedActivity),
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

  String _unitForActivity(String key) {
    switch (key) {
      case 'pushups':
      case 'situps':
        return 'reps';
      case 'vertical_jump':
        return 'cm';
      case 'shuttle_run':
      case 'endurance_run':
        return 's';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071018),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Leaderboard',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Top performers',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
            tooltip: 'Refresh',
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
            // Selector Card
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
                child: Row(
                  children: [
                    const Icon(Icons.leaderboard, color: Colors.white70),
                    const SizedBox(width: 2),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedActivity,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0B1220),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        dropdownColor: const Color(0xFF0B1220),
                        items: _activities
                            .map(
                              (a) => DropdownMenuItem(
                                value: a,
                                child: Text(
                                  a.replaceAll('_', ' ').toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selectedActivity = v);
                          _loadLeaderboard();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _loadLeaderboard,
                      icon: const Icon(
                        Icons.refresh,
                        color: Colors.white70,
                        size: 18,
                      ),
                      label: const Text(
                        'Reload',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

            if (_error != null)
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

            // My rank tile
            if (_myRank != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1820),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events, color: Colors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your Rank: $_myRank ${_myBest != null ? " — ${_myBest!['score']} ${_unitForActivity(_selectedActivity)}" : ""}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (_myBest == null)
                        Text(
                          'No record',
                          style: TextStyle(color: Colors.white54),
                        ),
                    ],
                  ),
                ),
              ),

            // List header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: const [
                  Expanded(
                    child: Text(
                      'Players',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Score',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10, height: 1),

            // Leader tiles
            if (!_loading && _leaders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _error ?? 'No scores yet',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ),

            ..._leaders.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              return _buildLeaderTile(row, idx, uid);
            }),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
