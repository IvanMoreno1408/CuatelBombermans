// lib/services/session.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'user_lookup.dart';

/// Cierra sesión de Firebase y limpia caches globales de la app.
Future<void> appSignOut() async {
  await FirebaseAuth.instance.signOut();
  // Limpia caché de nombres/usuarios (evita fugas entre cuentas)
  UserLookup.instance.clear();
}
