import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AthleteProfilePage extends StatelessWidget {
  final Map<String, dynamic> player;

  const AthleteProfilePage({super.key, required this.player});

  Future<void> _openGmail(String email) async {
    final Uri gmailUri = Uri.parse(
      "googlegmail://co?to=$email&subject=SAI Talent Selection Discussion",
    );

    final Uri mailtoUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=SAI Talent Selection Discussion',
    );

    try {
      if (await canLaunchUrl(gmailUri)) {
        await launchUrl(gmailUri);
      } else {
        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRaw = player['user'];
    final bestTrialsRaw = player['bestTrials'];

    final Map<String, dynamic> user = userRaw is Map<String, dynamic>
        ? userRaw
        : {};

    final Map<String, dynamic> bestTrials =
        bestTrialsRaw is Map<String, dynamic> ? bestTrialsRaw : {};

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
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              /// ================= HEADER CARD =================
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Name
                    Text(
                      player['name'] ?? "Unknown Athlete",
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 15),

                    /// Sport & Category Badges
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _badge(player['sport'] ?? "Sport", Colors.orange),
                        _badge(
                          player['category'] ?? "Category",
                          Colors.greenAccent,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    /// Contact Button
                    if (player['email'] != null &&
                        player['email'].toString().isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _openGmail(player['email']),
                          icon: const Icon(Icons.email),
                          label: const Text(
                            "Contact Athlete",
                            style: TextStyle(
                              color: Color.fromARGB(255, 81, 188, 238),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              /// ================= BIO CARD =================
              _sectionTitle("Athlete Bio"),

              const SizedBox(height: 15),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildBioRow("Age", user['age'] ?? "-"),
                    _buildBioRow("Gender", user['gender'] ?? "-"),
                    _buildBioRow("Height", "${user['height'] ?? "-"} cm"),
                    _buildBioRow("Weight", "${user['weight'] ?? "-"} kg"),
                    _buildBioRow("Chest", "${user['chest'] ?? "-"} cm"),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              /// ================= PERFORMANCE =================
              _sectionTitle("Best Performance"),

              const SizedBox(height: 15),

              if (bestTrials.isEmpty)
                const Text(
                  "No trial data available.",
                  style: TextStyle(color: Colors.white),
                )
              else
                ...bestTrials.entries.map((entry) {
                  final trial = entry.value;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${trial['score']} ${trial['unit']}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBioRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
