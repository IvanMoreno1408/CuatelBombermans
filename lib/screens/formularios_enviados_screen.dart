// lib/screens/formularios_enviados_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/loading_indicator.dart';
import 'formulario_detalle_screen.dart';

// Paleta corporativa
const _brandBlue = Color(0xFF0E4DA4);
const _brandBlueDark = Color(0xFF0A3A7B);
const _brandYellow = Color(0xFFFFC107);

class FormulariosEnviadosScreen extends StatefulWidget {
  const FormulariosEnviadosScreen({super.key});

  @override
  State<FormulariosEnviadosScreen> createState() =>
      _FormulariosEnviadosScreenState();
}

class _FormulariosEnviadosScreenState extends State<FormulariosEnviadosScreen> {
  String? _selectedTemplateId;
  DateTimeRange? _range;

  // Roles / alcance
  bool _isAdmin = false;
  bool _isLeader = false;
  bool _isSupervisor = false;
  bool get _isElevated => _isAdmin || _isLeader || _isSupervisor;

  bool _viewAll = false; // si es elevado, puede alternar ver todos
  String? _userProjectId; // necesario para líder en "Todos"

  // cachear plantillas
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _templatesFuture;

  @override
  void initState() {
    super.initState();
    _templatesFuture = _loadTemplatesOnce();
    _initRoleAndProfile(); // detectar rol + proyecto al montar
  }

  // -------- helpers de normalización ----------
  bool _rolesContains(dynamic roles, String value) {
    if (roles is List) {
      return roles.any((e) => e.toString().toLowerCase() == value);
    }
    return false;
  }

  Future<void> _initRoleAndProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1) custom claims
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? {};
      final roleClaim = (claims['role'] as String?)?.toLowerCase();
      final rolesClaim =
          (claims['roles'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          const [];

      // 2) doc usuarios/{uid}
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final data = userDoc.data() ?? {};
      final rolesDoc =
          (data['roles'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          const [];
      final projectId = (data['proyectoId'] as String?)?.trim();

      // 3) merge de roles (claims + doc)
      final isAdmin =
          roleClaim == 'admin' ||
          _rolesContains(rolesClaim, 'admin') ||
          _rolesContains(rolesDoc, 'admin');

      final isLeader =
          roleClaim == 'lider' ||
          roleClaim == 'líder' ||
          _rolesContains(rolesClaim, 'lider') ||
          _rolesContains(rolesClaim, 'líder') ||
          _rolesContains(rolesDoc, 'lider') ||
          _rolesContains(rolesDoc, 'líder');

      final isSupervisor =
          roleClaim == 'supervisor' ||
          _rolesContains(rolesClaim, 'supervisor') ||
          _rolesContains(rolesDoc, 'supervisor');

      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _isLeader = isLeader;
          _isSupervisor = isSupervisor;
          _userProjectId = projectId;
          _viewAll =
              _isElevated; // por defecto, si es elevado, empieza en "Todos"
        });
      }
    } catch (_) {
      // silencio: si falla, seguirá viendo sus propios envíos
    }
  }

  /// Asegura que tenemos el perfil (para líder -> proyectoId) antes de construir query
  Future<void> _ensureUserProfileLoaded(String uid) async {
    if (_userProjectId != null || !_isLeader) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final data = userDoc.data() ?? {};
      if (mounted) {
        setState(() {
          _userProjectId = (data['proyectoId'] as String?)?.trim();
        });
      }
    } catch (_) {}
  }

  /// Stream base que espera usuario autenticado y construye la query según alcance y rol (alineado a TUS REGLAS)
  Stream<QuerySnapshot<Map<String, dynamic>>> _baseStream() async* {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      user = await FirebaseAuth.instance.authStateChanges().firstWhere(
        (u) => u != null,
      );
    }

    // Si es líder y quiere ver "Todos", necesitamos tener su proyectoId para filtrar
    if (_isLeader &&
        _viewAll &&
        (_userProjectId == null || _userProjectId!.isEmpty)) {
      await _ensureUserProfileLoaded(user!.uid);
    }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'formularios_registros',
    );

    // LÓGICA DE ALCANCE:
    // - Admin/Supervisor:
    //    * viewAll = true  -> sin filtro por uid (ven todo)
    //    * viewAll = false -> solo sus envíos
    // - Líder:
    //    * viewAll = true  -> filtrar por proyectoId (regla lo exige)
    //    * viewAll = false -> solo sus envíos
    if (_isAdmin || _isSupervisor) {
      if (!_viewAll) {
        q = q.where('uid', isEqualTo: user!.uid);
      }
    } else if (_isLeader) {
      if (_viewAll) {
        // Cumple la regla: líder solo puede leer registros con su mismo proyectoId
        if (_userProjectId != null && _userProjectId!.isNotEmpty) {
          q = q.where('proyectoId', isEqualTo: _userProjectId);
        } else {
          // fallback seguro: si no tenemos proyecto, no hacemos consulta abierta
          q = q.where('uid', isEqualTo: user!.uid);
        }
      } else {
        q = q.where('uid', isEqualTo: user!.uid);
      }
    } else {
      // Usuario sin rol elevado: siempre sus envíos
      q = q.where('uid', isEqualTo: user!.uid);
    }

    if (_selectedTemplateId != null && _selectedTemplateId!.isNotEmpty) {
      q = q.where('templateId', isEqualTo: _selectedTemplateId);
    }

    yield* q.snapshots();
  }

  // Solo rango de fechas en cliente
  bool _matchesClientFilters(Map<String, dynamic> doc) {
    if (_range != null && doc['createdAt'] is Timestamp) {
      final dt = (doc['createdAt'] as Timestamp).toDate();
      final start = DateTime(
        _range!.start.year,
        _range!.start.month,
        _range!.start.day,
      );
      final end = DateTime(
        _range!.end.year,
        _range!.end.month,
        _range!.end.day,
        23,
        59,
        59,
      );
      if (dt.isBefore(start) || dt.isAfter(end)) return false;
    }
    return true;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadTemplatesOnce() async {
    final qs = await FirebaseFirestore.instance
        .collection('formularios_templates')
        .orderBy('nombre')
        .get();
    return qs.docs;
  }

  String _formatFecha(DateTime? ts) {
    if (ts == null) return '—';
    final d = ts.day.toString().padLeft(2, '0');
    final m = ts.month.toString().padLeft(2, '0');
    final y = ts.year.toString();
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final isTablet = w >= 600 && w < 1024;
          final isDesktop = w >= 1024;
          final maxBodyWidth = isDesktop
              ? 1200.0
              : (isTablet ? 920.0 : double.infinity);

          final rangeLabel = _range == null
              ? 'Fecha'
              : '${_range!.start.day}/${_range!.start.month}/${_range!.start.year} — '
                    '${_range!.end.day}/${_range!.end.month}/${_range!.end.year}';

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_brandBlue, _brandBlueDark],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBodyWidth),
                  child: Column(
                    children: [
                      _Header(
                        compact: w < 420,
                        hasRange: _range != null,
                        rangeLabel: rangeLabel,
                        onPickDate: () async {
                          final now = DateTime.now();
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(now.year - 2),
                            lastDate: DateTime(now.year + 1),
                            initialDateRange:
                                _range ??
                                DateTimeRange(
                                  start: DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                  ).subtract(const Duration(days: 7)),
                                  end: DateTime(now.year, now.month, now.day),
                                ),
                          );
                          if (picked != null) setState(() => _range = picked);
                        },
                        onClearDate: () => setState(() => _range = null),
                        templateFilter:
                            FutureBuilder<
                              List<QueryDocumentSnapshot<Map<String, dynamic>>>
                            >(
                              future: _templatesFuture,
                              builder: (context, snap) {
                                final docs =
                                    snap.data ??
                                    const <
                                      QueryDocumentSnapshot<
                                        Map<String, dynamic>
                                      >
                                    >[];
                                final items = <DropdownMenuItem<String>>[
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Todas las plantillas'),
                                  ),
                                  ...docs.map((d) {
                                    final m = d.data();
                                    final nombre = (m['nombre'] ?? d.id)
                                        .toString();
                                    return DropdownMenuItem(
                                      value: d.id,
                                      child: Text(
                                        nombre,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                ];
                                return DropdownButtonFormField<String>(
                                  value: _selectedTemplateId ?? '',
                                  items: items,
                                  onChanged: (v) => setState(
                                    () => _selectedTemplateId =
                                        (v ?? '').isEmpty ? null : v,
                                  ),
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                        // Toggle de alcance (admins / supervisores / líderes)
                        showScopeToggle: _isElevated,
                        viewAll: _viewAll,
                        onToggleViewAll: (v) => setState(() => _viewAll = v),
                      ),

                      // ===== CONTENIDO =====
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 20,
                                offset: Offset(0, -2),
                              ),
                            ],
                          ),
                          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _baseStream(),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: LoadingIndicator(
                                    message: 'Cargando envíos…',
                                  ),
                                );
                              }
                              if (snap.hasError) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Error: ${snap.error}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.red.shade400,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final all =
                                  List<
                                    QueryDocumentSnapshot<Map<String, dynamic>>
                                  >.from(snap.data?.docs ?? []);

                              // Orden DESC por createdAt en cliente
                              all.sort((a, b) {
                                final ta =
                                    (a.data()['createdAt'] as Timestamp?)
                                        ?.millisecondsSinceEpoch ??
                                    0;
                                final tb =
                                    (b.data()['createdAt'] as Timestamp?)
                                        ?.millisecondsSinceEpoch ??
                                    0;
                                return tb.compareTo(ta);
                              });

                              final filtered = all
                                  .where((d) => _matchesClientFilters(d.data()))
                                  .toList();

                              // Encabezado contador
                              Widget header = Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    _CounterPill(
                                      count: filtered.length,
                                      label: filtered.length == 1
                                          ? 'envío'
                                          : 'envíos',
                                    ),
                                    const Spacer(),
                                    if (_selectedTemplateId != null ||
                                        _range != null)
                                      TextButton.icon(
                                        onPressed: () => setState(() {
                                          _selectedTemplateId = null;
                                          _range = null;
                                        }),
                                        icon: const Icon(
                                          Icons.filter_alt_off_outlined,
                                        ),
                                        label: const Text('Limpiar filtros'),
                                      ),
                                  ],
                                ),
                              );

                              if (filtered.isEmpty) {
                                return ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    24,
                                  ),
                                  children: [
                                    header,
                                    const SizedBox(height: 24),
                                    _EmptyState(
                                      onClear: () {
                                        setState(() {
                                          _selectedTemplateId = null;
                                          _range = null;
                                        });
                                      },
                                    ),
                                  ],
                                );
                              }

                              // responsive: en móvil usa LISTA; en tablet/desktop GRID
                              final crossAxisCount = isDesktop
                                  ? 3
                                  : (isTablet ? 2 : 1);
                              const double gridMainAxisExtent = 132.0;

                              return CustomScrollView(
                                slivers: [
                                  SliverToBoxAdapter(child: header),

                                  if (crossAxisCount == 1)
                                    SliverList.builder(
                                      itemCount: filtered.length,
                                      itemBuilder: (context, i) {
                                        final d = filtered[i];
                                        final m = d.data();
                                        final ts =
                                            (m['createdAt'] as Timestamp?)
                                                ?.toDate();
                                        final templateNombre =
                                            (m['templateNombre'] ??
                                                    m['templateId'] ??
                                                    'Formulario')
                                                .toString();
                                        final Map<String, dynamic> data =
                                            (m['data']
                                                as Map<String, dynamic>?) ??
                                            const {};

                                        final proyectoNombre =
                                            (data['proyecto']?['nombre'] ??
                                                    data['obra']?['nombre'] ??
                                                    data['equipo']?['nombre'] ??
                                                    '—')
                                                .toString();

                                        int firmas = 0;
                                        data.forEach((k, v) {
                                          if (v is Map &&
                                              v['url'] is String &&
                                              (v['url'] as String).isNotEmpty) {
                                            firmas++;
                                          }
                                        });

                                        return Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            8,
                                            16,
                                            8,
                                          ),
                                          child: _RegistroCard(
                                            title: templateNombre,
                                            subtitle: proyectoNombre,
                                            fecha: _formatFecha(ts),
                                            badges: [
                                              if (firmas > 0)
                                                Chip(
                                                  label: Text(
                                                    '$firmas firma${firmas == 1 ? '' : 's'}',
                                                  ),
                                                  visualDensity:
                                                      const VisualDensity(
                                                        horizontal: -4,
                                                        vertical: -4,
                                                      ),
                                                ),
                                            ],
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      FormularioDetalleScreen(
                                                        docId: d.id,
                                                      ),
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    )
                                  else
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        24,
                                      ),
                                      sliver: SliverGrid(
                                        delegate: SliverChildBuilderDelegate((
                                          context,
                                          i,
                                        ) {
                                          final d = filtered[i];
                                          final m = d.data();
                                          final ts =
                                              (m['createdAt'] as Timestamp?)
                                                  ?.toDate();
                                          final templateNombre =
                                              (m['templateNombre'] ??
                                                      m['templateId'] ??
                                                      'Formulario')
                                                  .toString();
                                          final Map<String, dynamic> data =
                                              (m['data']
                                                  as Map<String, dynamic>?) ??
                                              const {};

                                          final proyectoNombre =
                                              (data['proyecto']?['nombre'] ??
                                                      data['obra']?['nombre'] ??
                                                      data['equipo']?['nombre'] ??
                                                      '—')
                                                  .toString();

                                          int firmas = 0;
                                          data.forEach((k, v) {
                                            if (v is Map &&
                                                v['url'] is String &&
                                                (v['url'] as String)
                                                    .isNotEmpty) {
                                              firmas++;
                                            }
                                          });

                                          return _RegistroCard(
                                            title: templateNombre,
                                            subtitle: proyectoNombre,
                                            fecha: _formatFecha(ts),
                                            badges: [
                                              if (firmas > 0)
                                                Chip(
                                                  label: Text(
                                                    '$firmas firma${firmas == 1 ? '' : 's'}',
                                                  ),
                                                  visualDensity:
                                                      const VisualDensity(
                                                        horizontal: -4,
                                                        vertical: -4,
                                                      ),
                                                ),
                                            ],
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      FormularioDetalleScreen(
                                                        docId: d.id,
                                                      ),
                                                ),
                                              );
                                            },
                                          );
                                        }, childCount: filtered.length),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: crossAxisCount,
                                              crossAxisSpacing: 12,
                                              mainAxisSpacing: 12,
                                              mainAxisExtent:
                                                  gridMainAxisExtent,
                                            ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool compact;
  final bool hasRange;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final String rangeLabel;
  final Widget templateFilter;

  // Toggle de alcance
  final bool showScopeToggle;
  final bool viewAll;
  final ValueChanged<bool> onToggleViewAll;

  const _Header({
    required this.compact,
    required this.hasRange,
    required this.onPickDate,
    required this.onClearDate,
    required this.rangeLabel,
    required this.templateFilter,
    this.showScopeToggle = false,
    this.viewAll = false,
    required this.onToggleViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título + acción secundaria
          Row(
            children: [
              const Icon(Icons.outbox_rounded, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Enviados',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (compact)
                IconButton(
                  tooltip: 'Rango de fechas',
                  onPressed: onPickDate,
                  color: Colors.white,
                  icon: const Icon(Icons.event),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Píldora de rango (amarilla)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RangePill(
                label: rangeLabel,
                showClear: hasRange,
                onTap: onPickDate,
                onClear: onClearDate,
              ),

              // Toggle de alcance (admins/supervisores/líderes)
              if (showScopeToggle) ...[
                ChoiceChip(
                  label: const Text('Mis envíos'),
                  selected: !viewAll,
                  onSelected: (_) => onToggleViewAll(false),
                  selectedColor: Colors.white,
                ),
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: viewAll,
                  onSelected: (_) => onToggleViewAll(true),
                  selectedColor: _brandYellow,
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // Dropdown de plantilla (sin label)
          SizedBox(width: double.infinity, child: templateFilter),
        ],
      ),
    );
  }
}

/// Pastilla grande para el rango de fechas, con icono y "×" integrado (amarilla)
class _RangePill extends StatelessWidget {
  final String label;
  final bool showClear;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _RangePill({
    required this.label,
    required this.showClear,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _brandYellow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.orange.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, size: 18, color: Colors.black87),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showClear) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Icon(Icons.close, size: 16, color: Colors.black87),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CounterPill extends StatelessWidget {
  final int count;
  final String label;
  const _CounterPill({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.inbox_outlined, size: 16),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _RegistroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String fecha;
  final List<Widget> badges;
  final VoidCallback onTap;

  const _RegistroCard({
    required this.title,
    required this.subtitle,
    required this.fecha,
    required this.badges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE8EEF8)),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _brandBlue.withOpacity(0.28)),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: _brandBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: const TextStyle(height: 1.2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: -8,
                        children: [
                          // Chip de fecha “azulito”
                          Chip(
                            label: Text(fecha),
                            backgroundColor: const Color(0xFFF2F6FD),
                            side: BorderSide(
                              color: _brandBlue.withOpacity(0.18),
                            ),
                            shape: const StadiumBorder(),
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                            visualDensity: const VisualDensity(
                              horizontal: -4,
                              vertical: -4,
                            ),
                          ),
                          ...badges,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onClear;
  const _EmptyState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.search_off_rounded, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        const Text('No hay formularios que coincidan con los filtros.'),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const Text('Quitar filtros'),
        ),
      ],
    );
  }
}
