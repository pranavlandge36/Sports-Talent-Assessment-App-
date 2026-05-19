import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> fetchBestScores(String userId) async {
    QuerySnapshot snapshot = await _firestore
        .collection('best_scores')
        .where('userId', isEqualTo: userId)
        .get();

    Map<String, dynamic> scores = {};

    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;

      String activityKey = data['activityKey'];
      scores[activityKey] = data['score'];
    }

    return scores;
  }

  Future<Map<String, dynamic>?> fetchNormativeData(
    int age,
    String gender,
  ) async {
    String docId = "${age}_$gender";

    var doc = await _firestore.collection('normative_data').doc(docId).get();

    if (doc.exists) {
      return doc.data();
    }

    return null;
  }
}
