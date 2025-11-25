// lib/screens/evidencia_detalle_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// (Opcional) siguen funcionando si los usas en el historial de reviews
import '../services/user_lookup.dart';
import '../widgets/reviewer_name.dart';
import '../widgets/loading_indicator.dart'; // 👈 loader unificado

// Paleta corporativa
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);

class EvidenciaDetalleScreen extends StatelessWidget {
  final String evidenciaPath;
  const EvidenciaDetalleScreen({super.key, required this.evidenciaPath});

  void _snack(BuildContext c, String m, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(
      c,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // === Helper: formatea fechaClave a YYYY/MM/DD ===
  String _formatFechaClave(dynamic raw) {
    // Si es Timestamp
    if (raw is Timestamp) {
      final d = raw.toDate();
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      return '$y/$m/$dd';
    }
    // Si es String
    if (raw is String) {
      final s = raw.replaceAll(RegExp(r'\D'), ''); // quita separadores
      if (s.length == 8) {
        final y = s.substring(0, 4);
        final m = s.substring(4, 6);
        final d = s.substring(6, 8);
        return '$y/$m/$d';
      }
      // Si no cumple, lo devuelve tal cual
      return raw;
    }
    return '-';
  }

  // Transacción: solo permite cambiar si sigue "pendiente"
  Future<void> _setEstado(
    BuildContext context,
    DocumentReference ref,
    String estado,
  ) async {
    try {
      final reviewerUid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw 'La evidencia no existe';
        }

        final data = Map<String, dynamic>.from(snap.data() as Map);
        final current = (data['estado'] ?? 'pendiente') as String;

        if (current != 'pendiente') {
          // No permitir más cambios
          throw 'Esta evidencia ya fue $current';
        }

        // 1) Estado + reviewedAt con serverTimestamp
        tx.set(ref, {
          'estado': estado,
          'reviewedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 2) Agregar entrada al historial usando hora del cliente
        tx.update(ref, {
          'reviews': FieldValue.arrayUnion([
            {
              'byUid': reviewerUid,
              'estado': estado,
              'at': Timestamp.now(), // no serverTimestamp dentro de arrays
            },
          ]),
        });
      });

      _snack(context, 'Marcado: ${_capitalize(estado)}', color: Colors.green);
    } catch (e) {
      _snack(context, 'No se pudo actualizar: $e', color: Colors.red);
    }
  }

  // Nombre del autor desde /usuarios/{uid}
  Widget _autorPill(String uidAutor) {
    final userRef = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uidAutor);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (_, snap) {
        String texto = 'Usuario: $uidAutor';
        if (snap.hasData && snap.data!.exists) {
          final u = snap.data!.data() ?? {};
          final nombre = (u['nombre'] ?? '') as String;
          final email = (u['email'] ?? '') as String;
          if (nombre.isNotEmpty) {
            texto = 'Usuario: $nombre';
          } else if (email.isNotEmpty) {
            texto = 'Usuario: $email';
          }
        }
        return _MetaPill(icon: Icons.person_outline, text: texto);
      },
    );
  }

  // Viewer a pantalla completa
  void _openFullImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Evidencia',
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.doc(evidenciaPath);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Evidencia'),
        backgroundColor: kCorpBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        // Las acciones aparecen solo si se puede revisar (estado == pendiente)
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: ref.snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || !snap.data!.exists) return const SizedBox();
              final m = Map<String, dynamic>.from(
                (snap.data!.data() ?? {}) as Map<String, dynamic>,
              )..removeWhere((k, v) => v == null);
              final estado = (m['estado'] ?? 'pendiente') as String;
              final canReview = estado == 'pendiente';

              if (!canReview) return const SizedBox();

              return Row(
                children: [
                  IconButton(
                    tooltip: 'Aprobar',
                    onPressed: () => _setEstado(context, ref, 'aprobado'),
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Rechazar',
                    onPressed: () => _setEstado(context, ref, 'rechazado'),
                    icon: const Icon(Icons.cancel, color: Colors.white),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: ref.snapshots(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: LoadingIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('La evidencia no existe.'));
          }

          final m = Map<String, dynamic>.from(
            snap.data!.data() as Map<String, dynamic>,
          )..removeWhere((k, v) => v == null);

          final titulo = (m['titulo'] ?? 'Reto') as String;
          final nota = (m['nota'] ?? '') as String;
          final imageUrl = m['imageUrl'] as String?;
          final estado = (m['estado'] ?? 'pendiente') as String;
          final fechaClaveFmt = _formatFechaClave(m['fechaClave']);
          final proyectoId = m['proyectoId'] as String?;
          final uidAutor = ref.parent.parent?.id ?? 'desconocido';
          final ts = (m['doneAt'] as Timestamp?)?.toDate();
          final hora = ts == null
              ? '-'
              : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

          // ¿Se puede revisar?
          final canReview = estado == 'pendiente';

          // Historial de revisiones (opcional)
          final rawReviews = (m['reviews'] as List?) ?? const [];
          final reviews =
              rawReviews
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
                ..sort((a, b) {
                  final ta =
                      (a['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  final tb =
                      (b['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  return tb.compareTo(ta);
                });

          // Prefetch de nombres para ReviewerName
          final uidsToPrefetch = reviews
              .map((r) => (r['byUid'] ?? '') as String)
              .where((u) => u.isNotEmpty)
              .toSet();
          if (uidsToPrefetch.isNotEmpty) {
            UserLookup.instance.prefetch(uidsToPrefetch);
          }

          // Colores del chip de estado
          Color chipBg, chipBd, chipFg;
          if (estado == 'aprobado') {
            chipBg = Colors.green.shade50;
            chipBd = Colors.green.shade300;
            chipFg = Colors.green.shade900;
          } else if (estado == 'rechazado') {
            chipBg = Colors.red.shade50;
            chipBd = Colors.red.shade300;
            chipFg = Colors.red.shade900;
          } else {
            chipBg = Colors.orange.shade50;
            chipBd = Colors.orange.shade300;
            chipFg = Colors.orange.shade900;
          }

          return ListView(
            children: [
              // ====== Encabezado con gradiente (responsive) ======
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1, -1),
                    end: Alignment(1, .2),
                    colors: [kCorpBlue, Color(0xFF3D8BFF)],
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Título + Sello final (si aplica)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  titulo,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              if (!canReview) _FinalBadge(estado: estado),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _StatusChip(
                                bg: chipBg,
                                bd: chipBd,
                                fg: chipFg,
                                label: _capitalize(estado),
                              ),
                              _PillLight(
                                icon: Icons.calendar_today_outlined,
                                text: 'Fecha: $fechaClaveFmt',
                              ),
                              _PillLight(
                                icon: Icons.schedule,
                                text: 'Hora: $hora',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _autorPill(uidAutor),
                              if (proyectoId != null)
                                StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>
                                >(
                                  stream: FirebaseFirestore.instance
                                      .collection('proyectos')
                                      .doc(proyectoId)
                                      .snapshots(),
                                  builder: (_, snap) {
                                    String texto = 'Proyecto: $proyectoId';
                                    if (snap.hasData && snap.data!.exists) {
                                      final data = snap.data!.data() ?? {};
                                      final nombre =
                                          (data['nombre'] ?? '') as String;
                                      if (nombre.isNotEmpty) {
                                        texto = 'Proyecto: $nombre';
                                      }
                                    }
                                    return _MetaPill(
                                      icon: Icons.apartment_outlined,
                                      text: texto,
                                    );
                                  },
                                ),
                              if (!canReview)
                                const _MetaPill(
                                  icon: Icons.lock_outline,
                                  text: 'Revisión finalizada',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ====== Contenido (responsive) ======
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (nota.isNotEmpty) ...[
                          const _SectionTitle('Nota'),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Text(
                              nota,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (imageUrl != null) ...[
                          const _SectionTitle('Evidencia (foto)'),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: GestureDetector(
                                onTap: () => _openFullImage(context, imageUrl),
                                child: Hero(
                                  tag: imageUrl,
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        if (reviews.isNotEmpty) ...[
                          const _SectionTitle('Historial de Revisiones'),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              children: reviews.map((r) {
                                final rEstado = (r['estado'] ?? '-') as String;
                                final rUid = (r['byUid'] ?? '-') as String;
                                final rTs = (r['at'] as Timestamp?)?.toDate();
                                final rHora = rTs == null
                                    ? '-'
                                    : '${rTs.hour.toString().padLeft(2, '0')}:${rTs.minute.toString().padLeft(2, '0')}';

                                Color pillBg, pillBd, pillFg;
                                if (rEstado == 'aprobado') {
                                  pillBg = Colors.green.shade50;
                                  pillBd = Colors.green.shade300;
                                  pillFg = Colors.green.shade900;
                                } else if (rEstado == 'rechazado') {
                                  pillBg = Colors.red.shade50;
                                  pillBd = Colors.red.shade300;
                                  pillFg = Colors.red.shade900;
                                } else {
                                  pillBg = Colors.grey.shade200;
                                  pillBd = Colors.grey.shade400;
                                  pillFg = Colors.black87;
                                }

                                return Column(
                                  children: [
                                    ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 2,
                                          ),
                                      leading: _StatusChip(
                                        bg: pillBg,
                                        bd: pillBd,
                                        fg: pillFg,
                                        label: _capitalize(rEstado),
                                        compact: true,
                                      ),
                                      title: ReviewerName(uid: rUid),
                                      subtitle: Text('Hora: $rHora'),
                                    ),
                                    const Divider(height: 1),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Acciones: solo visibles si se puede revisar
                        if (canReview) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _setEstado(context, ref, 'rechazado'),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Rechazar',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.red.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _setEstado(context, ref, 'aprobado'),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Aprobar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kCorpYellow,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
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
}

class _PillLight extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PillLight({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Color bg;
  final Color bd;
  final Color fg;
  final String label;
  final bool compact;
  const _StatusChip({
    required this.bg,
    required this.bd,
    required this.fg,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
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
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 18,
          decoration: BoxDecoration(
            color: kCorpBlue,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ],
    );
  }
}

// Sello visual para estado final (aprobado/rechazado)
class _FinalBadge extends StatelessWidget {
  final String estado;
  const _FinalBadge({required this.estado});

  @override
  Widget build(BuildContext context) {
    final bool aprobado = estado == 'aprobado';
    final Color bg = aprobado ? Colors.green.shade50 : Colors.red.shade50;
    final Color bd = aprobado ? Colors.green.shade300 : Colors.red.shade300;
    final Color fg = aprobado ? Colors.green.shade900 : Colors.red.shade900;
    final IconData icon = aprobado ? Icons.verified_outlined : Icons.block;

    return Transform.rotate(
      angle: -0.08, // leve inclinación estilo "sello"
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg.withOpacity(.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: bd, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              aprobado ? 'Aprobado' : 'Rechazado',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                letterSpacing: .3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
