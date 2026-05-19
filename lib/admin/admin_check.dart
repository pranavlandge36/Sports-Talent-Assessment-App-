import 'package:firebase_auth/firebase_auth.dart';

Future<bool> isAdminUser() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return false;

  final idTokenResult = await user.getIdTokenResult(true);

  return idTokenResult.claims?['role'] == 'admin';
}
