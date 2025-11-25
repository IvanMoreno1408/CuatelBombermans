// lib/screens/admin_projects_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/roles.dart';
import 'evidencias_screen.dart';
import 'package:lottie/lottie.dart';

// Paleta corporativa (misma que usamos en otras pantallas)
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);
const kCorpBlueDark = Color(0xFF0A3A7B); // 👈 azul oscuro para el gradiente

class AdminProjectsScreen extends StatelessWidget {
  final bool isAdmin;
  final String? leaderProjectId;

  const AdminProjectsScreen({
    super.key,
    this.isAdmin = false,
    this.leaderProjectId,
  });

  void _snack(BuildContext c, String m, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(
      c,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  // ============ Helpers de entrada / CC ============

  String _sanitizeCc(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  Future<String?> _askCc(
    BuildContext context, {
    required String title,
    String label = 'Cédula (solo números)',
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(dialogContext, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final v = _sanitizeCc(ctrl.text.trim());
      return v.isEmpty ? null : v;
    }
    return null;
  }

  /// Resuelve uid por CC en cc_index (docId = cc)
  Future<String?> _findUidByCc(String cc) async {
    final snap = await FirebaseFirestore.instance
        .collection('cc_index')
        .doc(cc)
        .get();
    if (!snap.exists) return null;
    final data = snap.data() ?? {};
    final uid = data['uid'] as String?;
    return (uid != null && uid.isNotEmpty) ? uid : null;
  }

  // ============ Acciones de proyectos ============

  Future<void> _createProject(BuildContext context) async {
    final name = await _askProjectNameSheet(context);
    if (name == null) return;

    try {
      await FirebaseFirestore.instance.collection('proyectos').add({
        'nombre': name,
        'activo': true,
        'lideres': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
      _snack(context, 'Proyecto creado ✅', color: Colors.green);
    } catch (_) {
      _snack(context, 'No se pudo crear', color: Colors.red);
    }
  }

  /// Sheet moderno para nombre de proyecto (más bonito y sin errores de pop)
  Future<String?> _askProjectNameSheet(BuildContext context) async {
    String value = '';
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              final canCreate = value.trim().isNotEmpty;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.apartment_rounded, color: kCorpBlue),
                      const SizedBox(width: 8),
                      const Text(
                        'Nuevo proyecto',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onChanged: (v) => setModalState(() => value = v),
                    onSubmitted: (_) {
                      if (value.trim().isNotEmpty) {
                        Navigator.pop(sheetContext, value.trim());
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Nombre del proyecto',
                      hintText: 'Ej: Proyecto Norte',
                      filled: true,
                      fillColor: const Color(0xFFF6F7FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: canCreate
                              ? () => Navigator.pop(sheetContext, value.trim())
                              : null,
                          icon: const Icon(Icons.check),
                          label: const Text('Crear'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kCorpYellow,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.black12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ======= Toggle / Delete =======

  Future<void> _toggleActivo(BuildContext c, String id, bool activo) async {
    try {
      await FirebaseFirestore.instance.collection('proyectos').doc(id).set({
        'activo': !activo,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      _snack(c, 'No se pudo cambiar estado', color: Colors.red);
    }
  }

  Future<void> _deleteProject(BuildContext c, String id) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar proyecto'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final fs = FirebaseFirestore.instance;
      final projRef = fs.collection('proyectos').doc(id);

      // Obtener líderes para degradar después
      final projSnap = await projRef.get();
      final pdata = projSnap.data() ?? {};
      final lideres = ((pdata['lideres'] ?? []) as List).cast<String>();

      await projRef.delete();

      for (final uid in lideres) {
        await RolesService.instance.demoteLeaderIfNoProjects(uid);
      }

      _snack(c, 'Proyecto eliminado');
    } catch (_) {
      _snack(c, 'No se pudo eliminar', color: Colors.red);
    }
  }

  // ============ Líderes / Miembros (por CC) ============

  Future<void> _addLeaderByCc(BuildContext c, String proyId) async {
    final cc = await _askCc(c, title: 'Agregar líder por CC');
    if (cc == null) return;

    final fs = FirebaseFirestore.instance;
    final projRef = fs.collection('proyectos').doc(proyId);

    try {
      final uid = await _findUidByCc(cc);
      if (uid == null) {
        _snack(
          c,
          'No existe un usuario con esa cédula. Regístralo primero.',
          color: Colors.red,
        );
        return;
      }
      final userRef = fs.collection('usuarios').doc(uid);

      await fs.runTransaction((tx) async {
        final projSnap = await tx.get(projRef);
        if (!projSnap.exists) {
          throw Exception('NO_PROJECT');
        }

        final pdata = projSnap.data() ?? {};
        final lideres = ((pdata['lideres'] ?? []) as List)
            .cast<String>()
            .toSet();

        if (!lideres.contains(uid)) {
          lideres.add(uid);
          tx.set(projRef, {
            'lideres': lideres.toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        // 🔒 Importante: no sobreescribir roles; usar arrayUnion
        tx.set(userRef, {
          'roles': FieldValue.arrayUnion(['lider']),
          'proyectoId': proyId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      // Refuerzo en servicio (no borra otros roles)
      await RolesService.instance.promoteToLeader(uid);
      _snack(c, 'Líder agregado ✅', color: Colors.green);
    } catch (e) {
      if (e is FirebaseException) {
        _snack(
          c,
          'Error (${e.code}): ${e.message ?? 'acción no permitida'}',
          color: Colors.red,
        );
      } else if (e.toString().contains('NO_PROJECT')) {
        _snack(c, 'Proyecto inexistente', color: Colors.red);
      } else {
        _snack(c, 'No se pudo agregar líder', color: Colors.red);
      }
    }
  }

  Future<void> _removeLeader(BuildContext c, String proyId, String uid) async {
    if (!isAdmin) {
      _snack(c, 'No tienes permisos para remover líderes', color: Colors.red);
      return;
    }
    try {
      final refProj = FirebaseFirestore.instance
          .collection('proyectos')
          .doc(proyId);
      await refProj.update({
        'lideres': FieldValue.arrayRemove([uid]),
      });

      await RolesService.instance.demoteLeaderIfNoProjects(uid);
      _snack(c, 'Líder removido');
    } catch (e) {
      if (e is FirebaseException) {
        _snack(c, 'Error (${e.code}): ${e.message ?? ''}', color: Colors.red);
      } else {
        _snack(c, 'No se pudo remover líder', color: Colors.red);
      }
    }
  }

  Future<void> _addMemberByCc(BuildContext c, String proyId) async {
    final cc = await _askCc(c, title: 'Agregar miembro por CC');
    if (cc == null) return;

    try {
      final uid = await _findUidByCc(cc);
      if (uid == null) {
        _snack(
          c,
          'No existe un usuario con esa cédula. Regístralo primero.',
          color: Colors.red,
        );
        return;
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'proyectoId': proyId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack(c, 'Miembro asignado ✅', color: Colors.green);
    } catch (e) {
      if (e is FirebaseException) {
        _snack(c, 'Error (${e.code}): ${e.message ?? ''}', color: Colors.red);
      } else {
        _snack(c, 'No se pudo asignar', color: Colors.red);
      }
    }
  }

  Future<void> _removeMember(BuildContext c, String uid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // 1) Un líder no puede removerse a sí mismo
    if (!isAdmin && uid == currentUid) {
      _snack(c, 'No puedes removerte a ti mismo del proyecto');
      return;
    }

    try {
      // 2) Defensa extra: si objetivo es líder del proyecto, bloquear (solo líderes)
      if (!isAdmin) {
        final myProyId = leaderProjectId;
        if (myProyId != null) {
          final isTargetLeader = await _isLeaderOfProject(
            uid: uid,
            projectId: myProyId,
          );
          final hasLeaderRole = await _hasLeaderRole(uid);
          if (isTargetLeader || hasLeaderRole) {
            _snack(
              c,
              'No puedes remover a un líder del proyecto',
              color: Colors.red,
            );
            return;
          }
        }
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'proyectoId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack(c, 'Miembro removido del proyecto');
    } catch (e) {
      if (e is FirebaseException) {
        _snack(c, 'Error (${e.code}): ${e.message ?? ''}', color: Colors.red);
      } else {
        _snack(c, 'No se pudo remover', color: Colors.red);
      }
    }
  }

  // ===== Helpers de validación cruzada =====
  Future<bool> _hasLeaderRole(String uid) async {
    final s = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    final roles = ((s.data()?['roles'] ?? []) as List).cast<String>();
    return roles.contains('lider');
  }

  Future<bool> _isLeaderOfProject({
    required String uid,
    required String projectId,
  }) async {
    final s = await FirebaseFirestore.instance
        .collection('proyectos')
        .doc(projectId)
        .get();
    final data = s.data() ?? {};
    final lideres = ((data['lideres'] ?? []) as List).cast<String>();
    return lideres.contains(uid);
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    // Admin: todos los proyectos; Líder: solo su proyecto
    final Stream<QuerySnapshot<Map<String, dynamic>>> stream = isAdmin
        ? FirebaseFirestore.instance
              .collection('proyectos')
              .orderBy('nombre')
              .snapshots()
        : (leaderProjectId == null
              ? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty()
              : FirebaseFirestore.instance
                    .collection('proyectos')
                    .where(FieldPath.documentId, isEqualTo: leaderProjectId)
                    .snapshots());

    final roleLabel = isAdmin ? 'Admin' : 'Líder';

    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _createProject(context),
              icon: const Icon(Icons.add),
              label: const Text('Crear proyecto'),
              backgroundColor: kCorpYellow,
              foregroundColor: Colors.black,
            )
          : null,
      body: Container(
        // ===== Fondo con gradiente (como en Retos/Ranking) =====
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kCorpBlue, kCorpBlueDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ======= HEADER estilo "Mis Retos" =======
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.apartment_rounded,
                      color: kCorpYellow,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAdmin ? 'Proyectos' : 'Mi Equipo',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _ChipBadge(
                      icon: Icons.verified_user_outlined,
                      label: roleLabel,
                      pillColor: kCorpYellow,
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Evidencias',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EvidenciasScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.verified_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // ======= CONTENIDO =======
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: stream,
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: Lottie.asset(
                            'lottie/loading.json',
                            width: 180,
                            height: 180,
                            repeat: true,
                            fit: BoxFit.contain,
                          ),
                        );
                      }
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Error proyectos: ${snap.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(child: Text('No hay proyectos.'));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final projDoc = docs[i];
                          final data = projDoc.data();
                          final activo = (data['activo'] ?? true) as bool;
                          final lideres = ((data['lideres'] ?? []) as List)
                              .cast<String>();
                          final nombre = (data['nombre'] ?? 'Proyecto')
                              .toString();

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                backgroundColor: Colors.white,
                                collapsedBackgroundColor: Colors.white,
                                leading: Icon(
                                  activo
                                      ? Icons.play_circle_outline
                                      : Icons.pause_circle,
                                  color: activo ? Colors.green : Colors.orange,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _statusChip(
                                      label: activo ? 'Activo' : 'Pausado',
                                      color: activo
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _metaPill(
                                        icon: Icons.verified_user_outlined,
                                        text: 'Líderes: ${lideres.length}',
                                      ),
                                      // Contador en vivo de miembros
                                      StreamBuilder<
                                        QuerySnapshot<Map<String, dynamic>>
                                      >(
                                        stream: FirebaseFirestore.instance
                                            .collection('usuarios')
                                            .where(
                                              'proyectoId',
                                              isEqualTo: projDoc.id,
                                            )
                                            .snapshots(),
                                        builder: (_, ms) {
                                          final count =
                                              ms.data?.docs.length ?? 0;
                                          return _metaPill(
                                            icon: Icons.groups_2_outlined,
                                            text: 'Miembros: $count',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                // ======== CONTENIDO ========
                                children: [
                                  const SizedBox(height: 8),

                                  // ----- LÍDERES -----
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _sectionTitle('Líderes'),
                                      if (isAdmin)
                                        TextButton.icon(
                                          onPressed: () => _addLeaderByCc(
                                            context,
                                            projDoc.id,
                                          ),
                                          icon: const Icon(
                                            Icons.person_add_alt_1,
                                          ),
                                          label: const Text('Agregar (CC)'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: kCorpBlue,
                                          ),
                                        ),
                                    ],
                                  ),
                                  FutureBuilder<
                                    List<
                                      QueryDocumentSnapshot<
                                        Map<String, dynamic>
                                      >
                                    >
                                  >(
                                    future: _loadUsersByUids(lideres),
                                    builder: (_, lSnap) {
                                      if (lSnap.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: LinearProgressIndicator(
                                            minHeight: 2,
                                          ),
                                        );
                                      }
                                      if (lSnap.hasError) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Text(
                                            'Error líderes: ${lSnap.error}',
                                            style: const TextStyle(
                                              color: Colors.red,
                                            ),
                                          ),
                                        );
                                      }
                                      final ls = lSnap.data ?? [];
                                      if (lideres.isEmpty || ls.isEmpty) {
                                        return const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: Text('Sin líderes asignados.'),
                                        );
                                      }
                                      return Column(
                                        children: ls.map((u) {
                                          final ud = u.data();
                                          final title =
                                              (ud['nombre'] ??
                                                      ud['email'] ??
                                                      u.id)
                                                  .toString();
                                          final subtitle = (ud['email'] ?? '')
                                              .toString();

                                          return ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: CircleAvatar(
                                              backgroundColor: kCorpBlue
                                                  .withOpacity(.12),
                                              child: Text(
                                                _initials(title, subtitle),
                                                style: const TextStyle(
                                                  color: kCorpBlue,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            title: Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Text(
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: isAdmin
                                                ? IconButton(
                                                    tooltip: 'Quitar líder',
                                                    icon: const Icon(
                                                      Icons.close,
                                                    ),
                                                    onPressed: () =>
                                                        _removeLeader(
                                                          context,
                                                          projDoc.id,
                                                          u.id,
                                                        ),
                                                  )
                                                : null,
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),

                                  // ----- MIEMBROS -----
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _sectionTitle('Miembros'),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _addMemberByCc(context, projDoc.id),
                                        icon: const Icon(
                                          Icons.group_add_outlined,
                                        ),
                                        label: const Text('Agregar (CC)'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: kCorpBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    stream: FirebaseFirestore.instance
                                        .collection('usuarios')
                                        .where(
                                          'proyectoId',
                                          isEqualTo: projDoc.id,
                                        )
                                        .snapshots(),
                                    builder: (_, mSnap) {
                                      if (mSnap.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: LinearProgressIndicator(
                                            minHeight: 2,
                                          ),
                                        );
                                      }
                                      if (mSnap.hasError) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Text(
                                            'Error miembros: ${mSnap.error}',
                                            style: const TextStyle(
                                              color: Colors.red,
                                            ),
                                          ),
                                        );
                                      }
                                      final ms = mSnap.data?.docs ?? [];
                                      if (ms.isEmpty) {
                                        return const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: Text('Sin miembros.'),
                                        );
                                      }

                                      // Orden cliente por email
                                      ms.sort((a, b) {
                                        final ae = (a.data()['email'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        final be = (b.data()['email'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        return ae.compareTo(be);
                                      });

                                      final currentUid = FirebaseAuth
                                          .instance
                                          .currentUser
                                          ?.uid;

                                      return Column(
                                        children: ms.map((u) {
                                          final ud = u.data();
                                          final title =
                                              (ud['nombre'] ??
                                                      ud['email'] ??
                                                      u.id)
                                                  .toString();
                                          final subtitle = (ud['email'] ?? '')
                                              .toString();
                                          final isSelf = (u.id == currentUid);

                                          // Doble chequeo: líder por arreglo y por rol
                                          final roles =
                                              ((ud['roles'] ?? []) as List)
                                                  .cast<String>();
                                          final isTargetLeader =
                                              roles.contains('lider') ||
                                              lideres.contains(u.id);

                                          // Si NO es admin: no puede removerse ni remover a líderes
                                          final canShowRemove =
                                              isAdmin ||
                                              (!isSelf && !isTargetLeader);

                                          return ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: CircleAvatar(
                                              backgroundColor:
                                                  Colors.grey.shade200,
                                              child: Text(
                                                _initials(title, subtitle),
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            title: Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: canShowRemove
                                                ? IconButton(
                                                    tooltip:
                                                        'Remover del proyecto',
                                                    icon: const Icon(
                                                      Icons
                                                          .remove_circle_outline,
                                                    ),
                                                    onPressed: () =>
                                                        _removeMember(
                                                          context,
                                                          u.id,
                                                        ),
                                                  )
                                                : null,
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),

                                  const Divider(height: 20),

                                  // ----- Acciones de proyecto -----
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _toggleActivo(
                                          context,
                                          projDoc.id,
                                          activo,
                                        ),
                                        icon: Icon(
                                          activo
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                        ),
                                        label: Text(
                                          activo ? 'Desactivar' : 'Activar',
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: activo
                                              ? Colors.orange
                                              : kCorpBlue,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (isAdmin)
                                        TextButton.icon(
                                          onPressed: () => _deleteProject(
                                            context,
                                            projDoc.id,
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          label: const Text(
                                            'Eliminar',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Carga usuarios por lotes (whereIn ≤ 10).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadUsersByUids(
    List<String> uids,
  ) async {
    final fs = FirebaseFirestore.instance;
    final result = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (uids.isEmpty) return result;

    const chunk = 10;
    for (var i = 0; i < uids.length; i += chunk) {
      final part = uids.sublist(
        i,
        i + chunk > uids.length ? uids.length : i + chunk,
      );
      final snap = await fs
          .collection('usuarios')
          .where(FieldPath.documentId, whereIn: part)
          .get();
      result.addAll(snap.docs);
    }
    return result;
  }
}

// ======= UI helpers =======

Widget _statusChip({required String label, required Color color}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color.shade900IfMaterial(),
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

Widget _metaPill({required IconData icon, required String text}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.black12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

Widget _sectionTitle(String text) {
  return Row(
    children: [
      const Icon(Icons.chevron_right, size: 18, color: Colors.black54),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    ],
  );
}

String _initials(String title, String email) {
  final src = (title.isNotEmpty ? title : email);
  final parts = src.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return ((parts[0].isNotEmpty ? parts[0][0] : '') +
            (parts[1].isNotEmpty ? parts[1][0] : ''))
        .toUpperCase();
  }
  return (src.isNotEmpty ? src[0] : '?').toUpperCase();
}

// Chip amarillo reutilizable (igual estilo que en otras pantallas)
class _ChipBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color pillColor;
  const _ChipBadge({
    required this.icon,
    required this.label,
    required this.pillColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// Pequeña extensión para elegir un tono legible si el color es MaterialColor
extension _Tone on Color {
  Color shade900IfMaterial() {
    if (this is MaterialColor) {
      final m = this as MaterialColor;
      return m.shade900;
    }
    return this;
  }
}
