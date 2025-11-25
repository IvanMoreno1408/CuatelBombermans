import 'package:cloud_firestore/cloud_firestore.dart';

/// Caché simple en memoria para mapear uid -> "Nombre (email)" o fallback al uid.
/// Uso:
///   final s = await UserLookup.instance.displayFor(uid);
///   // o en UI:
///   ReviewerName(uid: uid)
class UserLookup {
  UserLookup._();
  static final instance = UserLookup._();

  final _cache = <String, String>{};
  final _loading = <String, Future<String>>{};

  /// Devuelve "Nombre (email)" o "email" o el uid como último recurso.
  Future<String> displayFor(String uid) {
    if (_cache.containsKey(uid)) return Future.value(_cache[uid]);

    // Evitar lecturas duplicadas concurrentes
    if (_loading.containsKey(uid)) return _loading[uid]!;

    final fut = _fetch(uid);
    _loading[uid] = fut;
    return fut.whenComplete(() => _loading.remove(uid));
  }

  /// Precalienta varios uids (opcional)
  Future<void> prefetch(Iterable<String> uids) async {
    final uniques = uids
        .where((u) => u.isNotEmpty && !_cache.containsKey(u))
        .toSet();
    if (uniques.isEmpty) return;

    // Si son pocos, haces lecturas individuales; si son muchos, puedes batch por chunks.
    await Future.wait(uniques.map(displayFor));
  }

  Future<String> _fetch(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (!snap.exists) {
        _cache[uid] = uid;
        return uid;
      }

      final data = snap.data() ?? {};
      final nombre = (data['nombre'] as String?)?.trim();
      final email = (data['email'] as String?)?.trim();

      String result;
      if (nombre != null &&
          nombre.isNotEmpty &&
          email != null &&
          email.isNotEmpty) {
        result = '$nombre ($email)';
      } else if (nombre != null && nombre.isNotEmpty) {
        result = nombre;
      } else if (email != null && email.isNotEmpty) {
        result = email;
      } else {
        result = uid;
      }

      _cache[uid] = result;
      return result;
    } catch (_) {
      _cache[uid] = uid;
      return uid;
    }
  }

  void clear() => _cache.clear();
}
