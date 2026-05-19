import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SuspiciousPage extends StatelessWidget {
  const SuspiciousPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('assessments')
          .where('cheatScore', isGreaterThan: 0.6)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text("No suspicious attempts"));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index];

            return ListTile(
              leading: const Icon(Icons.warning, color: Colors.red),
              title: Text(data['displayName'] ?? "Unknown"),
              subtitle: Text("Activity: ${data['activityKey']}"),
              trailing: Text("Cheat: ${data['cheatScore']}"),
            );
          },
        );
      },
    );
  }
}
