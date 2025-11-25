import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio centralizado para gestionar roles.
/// - promoteToLeader(uid): sobrescribe roles = ['lider']
/// - demoteLeaderIfNoProjects(uid): si no lidera ningún proyecto, sobrescribe roles = ['operario']
class RolesService {
  RolesService._();
  static final RolesService instance = RolesService._();

  final _fs = FirebaseFirestore.instance;

  /// Promueve a líder forzando roles = ['lider'] (sobrescribe por requerimiento).
  Future<void> promoteToLeader(String uid) async {
    final userRef = _fs.collection('usuarios').doc(uid);
    await userRef.set({
      'roles': ['lider'],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Si el usuario NO aparece como líder en ningún proyecto → sobrescribe roles = ['operario'].
  Future<void> demoteLeaderIfNoProjects(String uid) async {
    // Busca proyectos donde el uid esté en 'lideres'
    final q = await _fs
        .collection('proyectos')
        .where('lideres', arrayContains: uid)
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      final userRef = _fs.collection('usuarios').doc(uid);
      await userRef.set({
        'roles': ['operario'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
