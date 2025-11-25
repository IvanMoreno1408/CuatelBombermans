// lib/screens/evidencias_screen.dart
import 'package:async/async.dart' show StreamZip;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'evidencia_detalle_screen.dart';
import '../widgets/loading_indicator.dart'; // 👈 loader unificado

// Paleta corporativa
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);
const kCorpBlueDark = Color(0xFF0A3A7B); // azul oscuro para gradiente

class EvidenciasScreen extends StatefulWidget {
  const EvidenciasScreen({super.key});

  @override
  State<EvidenciasScreen> createState() => _EvidenciasScreenState();
}

class _EvidenciasScreenState extends State<EvidenciasScreen> {
  String get _todayKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  // --- Filtro seleccionado ---
  String _estadoFiltro =
      'todos'; // 'todos' | 'pendiente' | 'aprobado' | 'rechazado'

  // --- tick para forzar resuscripción de streams al volver del detalle ---
  int _refreshTick = 0;

  // --- cache nombres de usuario ---
  final Map<String, String> _userNames = {};

  Future<String> _getUserName(String uid) async {
    if (_userNames.containsKey(uid)) return _userNames[uid]!;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final data = snap.data() ?? {};
      final nombre = (data['nombre'] ?? data['email'] ?? uid).toString();
      _userNames[uid] = nombre;
      return nombre;
    } catch (_) {
      return uid;
    }
  }

  // ====== UI helpers ======
  (Color bg, Color bd, Color fg) _estadoColors(String estado) {
    if (estado == 'aprobado') {
      return (
        Colors.green.shade50,
        Colors.green.shade300,
        Colors.green.shade900,
      );
    }
    if (estado == 'rechazado') {
      return (Colors.red.shade50, Colors.red.shade300, Colors.red.shade900);
    }
    return (Colors.grey.shade200, Colors.grey.shade400, Colors.grey.shade800);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _statusChip(String estado) {
    final (bg, bd, fg) = _estadoColors(estado);
    final label = _capitalize(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
        ),
      ),
    );
  }

  Widget _segmentedFilters() {
    Widget seg(String label, String value) {
      final selected = _estadoFiltro == value;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _estadoFiltro = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? kCorpYellow : const Color(0xFFF3F6FF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? kCorpYellow : const Color(0xFFE3E8FF),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: kCorpYellow.withOpacity(.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : kCorpBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          seg('Todos', 'todos'),
          const SizedBox(width: 8),
          seg('Pendiente', 'pendiente'),
          const SizedBox(width: 8),
          seg('Aprobado', 'aprobado'),
          const SizedBox(width: 8),
          seg('Rechazado', 'rechazado'),
        ],
      ),
    );
  }

  // Tarjeta SIN botones de aprobar/rechazar (sólo abre el detalle)
  Widget _evidenceCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> d,
    required String titulo,
    required String estado,
    required String autor,
    required DateTime? ts,
    required String? imageUrl,
    required VoidCallback onOpen,
  }) {
    final (bg, bd, _) = _estadoColors(estado);

    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // mini preview
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: Container(
                color: Colors.grey.shade200,
                width: 110,
                height: 88,
                child: imageUrl == null
                    ? const Icon(Icons.photo, size: 28, color: Colors.black45)
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image)),
                      ),
              ),
            ),
            // contenido
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // título + estado
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            titulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(estado),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // autor + hora
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            autor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.schedule,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ts == null
                              ? '-'
                              : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // pista de interacción (sin acciones)
                    Row(
                      children: [
                        const Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Toca para ver detalle',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // borde lateral según estado
            Container(
              width: 6,
              height: 88,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: bg,
                border: Border(left: BorderSide(color: bd, width: 2)),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======= BUILD =======
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: LoadingIndicator()));
    }

    final meRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);

    return Scaffold(
      body: Container(
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
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_outlined,
                      color: kCorpYellow,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Evidencias de hoy',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    // Chip rol
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: meRef.snapshots(),
                      builder: (_, s) {
                        String label = 'Operario';
                        final roles =
                            ((s.data?.data()?['roles'] ?? []) as List?)
                                ?.cast<String>() ??
                            const [];
                        if (roles.contains('admin')) {
                          label = 'Admin';
                        } else if (roles.contains('lider')) {
                          label = 'Líder';
                        }
                        return _ChipBadge(
                          icon: Icons.verified_user_outlined,
                          label: label,
                          pillColor: kCorpYellow,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Contenido superficie blanca
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        children: [
                          // Banner informativo
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: kCorpBlue,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Revisa las evidencias enviadas hoy. La aprobación/rechazo se realiza dentro del detalle.',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Filtros
                          _segmentedFilters(),

                          // Lista
                          Expanded(
                            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: meRef.snapshots(),
                              builder: (_, meSnap) {
                                if (meSnap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: LoadingIndicator(),
                                  );
                                }
                                if (meSnap.hasError) {
                                  return _err(
                                    'No se pudo leer tu perfil: ${meSnap.error}',
                                  );
                                }
                                if (!meSnap.hasData || !meSnap.data!.exists) {
                                  return _err(
                                    'Tu documento de usuario no existe.',
                                  );
                                }

                                final me = meSnap.data!.data() ?? {};
                                final roles = ((me['roles'] ?? []) as List)
                                    .cast<String>();
                                final isAdmin = roles.contains('admin');
                                final isLeader = roles.contains('lider');
                                final myProject =
                                    (me['proyectoId'] as String?) ?? '';

                                // 1) Stream de UIDs según rol
                                Stream<List<String>> uidsStream;
                                if (isAdmin) {
                                  uidsStream = FirebaseFirestore.instance
                                      .collection('usuarios')
                                      .snapshots()
                                      .map(
                                        (qs) =>
                                            qs.docs.map((d) => d.id).toList(),
                                      );
                                } else if (isLeader) {
                                  if (myProject.isEmpty) {
                                    return _err(
                                      'Eres líder pero no tienes proyecto asignado.',
                                    );
                                  }
                                  uidsStream = FirebaseFirestore.instance
                                      .collection('usuarios')
                                      .where('proyectoId', isEqualTo: myProject)
                                      .snapshots()
                                      .map(
                                        (qs) =>
                                            qs.docs.map((d) => d.id).toList(),
                                      );
                                } else {
                                  uidsStream = Stream.value([
                                    FirebaseAuth.instance.currentUser!.uid,
                                  ]);
                                }

                                // 2) Substreams de tareasDiarias(hoy)
                                return StreamBuilder<List<String>>(
                                  stream: uidsStream,
                                  builder: (_, uidsSnap) {
                                    if (uidsSnap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: LoadingIndicator(),
                                      );
                                    }
                                    if (uidsSnap.hasError) {
                                      return _err(
                                        'Error cargando usuarios: ${uidsSnap.error}',
                                      );
                                    }
                                    final uids = uidsSnap.data ?? const [];
                                    if (uids.isEmpty)
                                      return _empty(
                                        'Sin usuarios para revisar.',
                                      );

                                    final List<
                                      Stream<
                                        QuerySnapshot<Map<String, dynamic>>
                                      >
                                    >
                                    perUser = uids.map((u) {
                                      return FirebaseFirestore.instance
                                          .collection('usuarios')
                                          .doc(u)
                                          .collection('tareasDiarias')
                                          .where(
                                            'fechaClave',
                                            isEqualTo: _todayKey,
                                          )
                                          .snapshots();
                                    }).toList();

                                    final Stream<
                                      List<QuerySnapshot<Map<String, dynamic>>>
                                    >
                                    merged = perUser.length == 1
                                        ? perUser.first.map((s) => [s])
                                        : StreamZip(perUser);

                                    // 3) Unión de todos los docs
                                    return StreamBuilder<
                                      List<QuerySnapshot<Map<String, dynamic>>>
                                    >(
                                      key: ValueKey(
                                        _refreshTick,
                                      ), // 🔑 fuerza nueva suscripción tras volver del detalle
                                      stream: merged,
                                      builder: (_, mergedSnap) {
                                        if (mergedSnap.connectionState ==
                                            ConnectionState.waiting) {
                                          return const Center(
                                            child: LoadingIndicator(),
                                          );
                                        }
                                        if (mergedSnap.hasError) {
                                          return _err(
                                            'Error combinando resultados: ${mergedSnap.error}',
                                          );
                                        }

                                        final allDocs =
                                            <
                                              QueryDocumentSnapshot<
                                                Map<String, dynamic>
                                              >
                                            >[];
                                        for (final s
                                            in mergedSnap.data ?? const []) {
                                          allDocs.addAll(s.docs);
                                        }
                                        if (allDocs.isEmpty)
                                          return _empty('Sin evidencias hoy.');

                                        // filtro
                                        final filteredDocs =
                                            _estadoFiltro == 'todos'
                                            ? allDocs
                                            : allDocs
                                                  .where(
                                                    (d) =>
                                                        (d.data()['estado'] ??
                                                            'pendiente') ==
                                                        _estadoFiltro,
                                                  )
                                                  .toList();
                                        if (filteredDocs.isEmpty) {
                                          return _empty(
                                            'No hay evidencias con estado ${_capitalize(_estadoFiltro)}.',
                                          );
                                        }

                                        // ordenar por doneAt desc
                                        filteredDocs.sort((a, b) {
                                          final ta =
                                              (a.data()['doneAt'] as Timestamp?)
                                                  ?.millisecondsSinceEpoch ??
                                              0;
                                          final tb =
                                              (b.data()['doneAt'] as Timestamp?)
                                                  ?.millisecondsSinceEpoch ??
                                              0;
                                          return tb.compareTo(ta);
                                        });

                                        return ListView.separated(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            4,
                                            16,
                                            16,
                                          ),
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 12),
                                          itemCount: filteredDocs.length,
                                          itemBuilder: (_, i) {
                                            final d = filteredDocs[i];
                                            final m = d.data();
                                            final titulo =
                                                (m['titulo'] ?? 'Reto')
                                                    as String;
                                            final nota =
                                                (m['nota'] ?? '') as String;
                                            final imageUrl =
                                                m['imageUrl'] as String?;
                                            final estado =
                                                (m['estado'] ?? 'pendiente')
                                                    as String;
                                            final uidAutor =
                                                d.reference.parent.parent?.id ??
                                                'desconocido';
                                            final ts =
                                                (m['doneAt'] as Timestamp?)
                                                    ?.toDate();

                                            return FutureBuilder<String>(
                                              future: _getUserName(uidAutor),
                                              builder: (_, snapName) {
                                                final nombre =
                                                    snapName.data ?? uidAutor;
                                                return _evidenceCard(
                                                  d: d,
                                                  titulo: titulo,
                                                  estado: estado,
                                                  autor: nota.isNotEmpty
                                                      ? '$nombre • Nota: ${nota.length > 24 ? nota.substring(0, 24) + '…' : nota}'
                                                      : nombre,
                                                  ts: ts,
                                                  imageUrl: imageUrl,
                                                  onOpen: () async {
                                                    // ⤵️ Espera al detalle y fuerza refresh de streams
                                                    await Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            EvidenciaDetalleScreen(
                                                              evidenciaPath: d
                                                                  .reference
                                                                  .path,
                                                            ),
                                                      ),
                                                    );
                                                    if (!mounted) return;
                                                    setState(
                                                      () => _refreshTick++,
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _err(String msg) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text('Error:\n$msg', style: const TextStyle(color: Colors.red)),
  );

  Widget _empty(String msg) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const SizedBox(height: 8),
        Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
        const SizedBox(height: 8),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ],
    ),
  );
}

// ======= Chip amarillo reutilizable del header =======
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
