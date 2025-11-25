// lib/screens/admin_retos_list_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_reto_form_screen.dart';
import 'admin_projects_screen.dart';
import '../widgets/loading_indicator.dart'; // 👈 loader unificado

// Paleta corporativa (mismas del resto)
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);
const kCorpBlueDark = Color(0xFF0A3A7B); // 👈 azul oscuro para el gradiente

class AdminRetosListScreen extends StatefulWidget {
  const AdminRetosListScreen({super.key});

  @override
  State<AdminRetosListScreen> createState() => _AdminRetosListScreenState();
}

class _AdminRetosListScreenState extends State<AdminRetosListScreen> {
  final _searchCtrl = TextEditingController();

  // Filtros UI
  String _estado = 'activos'; // activos | todos | inactivos

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(BuildContext c, String m, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(
      c,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  Future<void> _toggleActiva(BuildContext c, String id, bool activa) async {
    try {
      await FirebaseFirestore.instance.collection('retos').doc(id).set({
        'activa': !activa,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      _snack(c, 'No se pudo cambiar el estado', color: Colors.red);
    }
  }

  Future<void> _borrar(BuildContext c, String id) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Reto'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('retos').doc(id).delete();
      _snack(c, 'Reto eliminado');
    } catch (_) {
      _snack(c, 'No se pudo eliminar', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('retos')
        .orderBy('orden', descending: false)
        .snapshots();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kCorpYellow,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Crear Reto'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminRetoFormScreen()),
          );
        },
      ),
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
              // ======= HEADER unificado =======
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      color: kCorpYellow,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Admin • Retos',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    const _ChipBadge(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Admin',
                      pillColor: kCorpYellow,
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Proyectos',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AdminProjectsScreen(isAdmin: true),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.apartment_outlined,
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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        children: [
                          // ====== Barra de búsqueda + filtros ======
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Search
                                TextField(
                                  controller: _searchCtrl,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Buscar por título o descripción…',
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: kCorpBlue,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF6F7FB),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE3E8FF),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE3E8FF),
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(14),
                                      ),
                                      borderSide: BorderSide(color: kCorpBlue),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Filtros de estado
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _pillFilter(
                                      label: 'Activos',
                                      selected: _estado == 'activos',
                                      onTap: () =>
                                          setState(() => _estado = 'activos'),
                                    ),
                                    _pillFilter(
                                      label: 'Inactivos',
                                      selected: _estado == 'inactivos',
                                      onTap: () =>
                                          setState(() => _estado = 'inactivos'),
                                    ),
                                    _pillFilter(
                                      label: 'Todos',
                                      selected: _estado == 'todos',
                                      onTap: () =>
                                          setState(() => _estado = 'todos'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // ====== Lista ======
                          Expanded(
                            child:
                                StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: stream,
                                  builder: (context, snap) {
                                    if (snap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: LoadingIndicator(),
                                      );
                                    }
                                    if (snap.hasError) {
                                      return Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          'Error: ${snap.error}',
                                          style: const TextStyle(
                                            color: Colors.red,
                                          ),
                                        ),
                                      );
                                    }

                                    final docs = (snap.data?.docs ?? [])
                                        .toList();

                                    // Filtros en memoria
                                    final q = _searchCtrl.text
                                        .trim()
                                        .toLowerCase();
                                    final filtered = docs.where((d) {
                                      final m = d.data();
                                      final activa =
                                          (m['activa'] ?? true) == true;

                                      final okEstado = switch (_estado) {
                                        'activos' => activa == true,
                                        'inactivos' => activa == false,
                                        _ => true,
                                      };

                                      var okSearch = true;
                                      if (q.isNotEmpty) {
                                        final titulo = (m['titulo'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        final desc = (m['descripcion'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        okSearch =
                                            titulo.contains(q) ||
                                            desc.contains(q);
                                      }

                                      return okEstado && okSearch;
                                    }).toList();

                                    if (filtered.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          'No hay retos que coincidan con los filtros.',
                                        ),
                                      );
                                    }

                                    return ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        12,
                                        100,
                                      ),
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, i) {
                                        final doc = filtered[i];
                                        final data = doc.data();
                                        final id = doc.id;

                                        final activa =
                                            (data['activa'] ?? true) == true;
                                        final xp = (data['xp'] ?? 0) as int;
                                        final orden =
                                            (data['orden'] ?? 0) as int;
                                        final titulo =
                                            (data['titulo'] ?? 'Reto')
                                                as String;
                                        final desc =
                                            (data['descripcion'] ?? '')
                                                as String;
                                        final tipo =
                                            (data['tipo'] ?? 'general')
                                                as String;
                                        final subrol =
                                            (data['subrol'] ?? '') as String;

                                        return _retoCard(
                                          context: context,
                                          id: id,
                                          activa: activa,
                                          titulo: titulo,
                                          descripcion: desc,
                                          xp: xp,
                                          orden: orden,
                                          tipo: tipo,
                                          subrol: subrol,
                                          onEdit: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    AdminRetoFormScreen(
                                                      retoId: id,
                                                      initialData: data,
                                                    ),
                                              ),
                                            );
                                          },
                                          onToggle: () => _toggleActiva(
                                            context,
                                            id,
                                            activa,
                                          ),
                                          onDelete: () => _borrar(context, id),
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

  // ---------- UI helpers ----------

  Widget _pillFilter({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    // Estilo consistente con chips de otras pantallas (amarillo seleccionado)
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
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
            fontWeight: FontWeight.w700,
            color: selected ? Colors.black : kCorpBlue,
          ),
        ),
      ),
    );
  }

  IconData _iconForTipo(String tipo) {
    switch (tipo) {
      case 'streak_bomba':
        return Icons.water_drop_outlined;
      case 'streak_grua':
        return Icons.construction_outlined;
      default:
        return Icons.flag_outlined;
    }
  }

  String _prettyTipo(String tipo) {
    switch (tipo) {
      case 'streak_bomba':
        return 'Racha bomba';
      case 'streak_grua':
        return 'Racha grúa';
      default:
        return 'General';
    }
  }

  String _prettySubrol(String subrol) {
    if (subrol == 'bomberman') return 'Bomberman';
    if (subrol == 'gruaman') return 'Gruaman';
    return subrol.isEmpty ? 'Todos' : subrol;
  }

  Color _colorForSubrol(String subrol) {
    if (subrol == 'bomberman') return Colors.orange.shade100;
    if (subrol == 'gruaman') return Colors.lightBlue.shade100;
    return Colors.grey.shade200;
  }

  Widget _retoCard({
    required BuildContext context,
    required String id,
    required bool activa,
    required String titulo,
    required String descripcion,
    required int xp,
    required int orden,
    required String tipo,
    required String subrol,
    required VoidCallback onEdit,
    required VoidCallback onToggle,
    required VoidCallback onDelete,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icono tipo
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Icon(_iconForTipo(tipo), color: kCorpBlue),
            ),
            const SizedBox(width: 10),

            // Texto + chips
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título + estado
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: activa
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: activa
                                ? Colors.green.shade300
                                : Colors.orange.shade300,
                          ),
                        ),
                        child: Text(
                          activa ? 'Activo' : 'Inactivo',
                          style: TextStyle(
                            fontSize: 11,
                            color: activa
                                ? Colors.green.shade900
                                : Colors.orange.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descripcion,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _chip('XP $xp', icon: Icons.flash_on_outlined),
                      _chip('Orden $orden', icon: Icons.sort),
                      _chip(_prettyTipo(tipo), icon: _iconForTipo(tipo)),
                      if (subrol.isNotEmpty)
                        _chip(
                          _prettySubrol(subrol),
                          icon: subrol == 'bomberman'
                              ? Icons.water_drop_outlined
                              : Icons.construction_outlined,
                          bg: _colorForSubrol(subrol),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Acciones
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'toggle') onToggle();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit),
                    title: Text('Editar'),
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(activa ? Icons.pause : Icons.play_arrow),
                    title: Text(activa ? 'Desactivar' : 'Activar'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text(
                      'Eliminar',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, {IconData? icon, Color? bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (bg ?? Colors.grey.shade100),
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.black87),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
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
