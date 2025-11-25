// lib/screens/formulario_lleno_screen.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/form_template.dart';
import '../widgets/signature_field.dart';
import '../widgets/loading_indicator.dart'; // 👈 loader unificado

// Paleta corporativa
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);

class FormularioLlenoScreen extends StatefulWidget {
  final FormTemplate template;
  const FormularioLlenoScreen({super.key, required this.template});

  @override
  State<FormularioLlenoScreen> createState() => _FormularioLlenoScreenState();
}

class _FormularioLlenoScreenState extends State<FormularioLlenoScreen> {
  final _formKey = GlobalKey<FormState>();

  /// Valores del formulario
  final Map<String, dynamic> _values = {};

  /// Controllers por campo de texto (para reflejar autollenado async)
  final Map<String, TextEditingController> _controllers = {};

  bool _saving = false;
  bool _hydratedDefaults = false;

  /// Proyecto del usuario para preseleccionar en dropdown
  String? _myProyectoId;

  void _snack(String m, {Color color = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  String _isoToday() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  TextEditingController _ctrlFor(String key, {String initial = ''}) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: initial),
    );
  }

  void _setValueAndController(String key, String text) {
    _values[key] = text;
    if (_controllers.containsKey(key)) {
      _controllers[key]!.text = text;
    }
  }

  // --- Autocompletar proyecto/obra/equipo, acta correlativa, recibido_por/cargo y fechas ---
  Future<void> _hydrateDefaultsOnce() async {
    if (_hydratedDefaults) return;
    _hydratedDefaults = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      final uSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final uData = uSnap.data() ?? {};

      _myProyectoId = (uData['proyectoId'] as String?) ?? '';
      final nombreUser =
          (uData['nombre'] as String?) ?? (user.email ?? 'Usuario');
      final roles = (uData['roles'] as List?)?.cast<String>() ?? const [];
      final rolPrincipal = roles.isEmpty ? 'operario' : roles.first;

      // 1) Prellenar proyecto/obra/equipo
      if ((_myProyectoId ?? '').isNotEmpty) {
        try {
          final projDoc = await FirebaseFirestore.instance
              .collection('proyectos')
              .doc(_myProyectoId)
              .get();
          final projName =
              (projDoc.data()?['nombre'] as String?) ?? _myProyectoId!;
          for (final k in const ['proyecto', 'obra', 'equipo']) {
            final exists = widget.template.campos.any((f) => f.key == k);
            if (exists) {
              _values[k] = {'id': _myProyectoId, 'nombre': projName};
            }
          }
        } catch (_) {}
      }

      // 2) Recibido por (nombre) y Cargo
      if (widget.template.campos.any((f) => f.key == 'recibido_por')) {
        _setValueAndController('recibido_por', nombreUser);
      }
      if (widget.template.campos.any((f) => f.key == 'cargo')) {
        _setValueAndController(
          'cargo',
          rolPrincipal,
        ); // se guarda sin modificar
      }

      // 3) N.º de acta correlativo
      if (widget.template.campos.any((f) => f.key == 'acta_numero')) {
        final q = await FirebaseFirestore.instance
            .collection('formularios_registros')
            .where('templateId', isEqualTo: widget.template.id)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

        int next = 1;
        if (q.docs.isNotEmpty) {
          final last = q.docs.first.data();
          final prev = (last['data']?['acta_numero'] ?? '') as String;
          final n = int.tryParse(prev.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          next = n + 1;
        }
        _setValueAndController('acta_numero', next.toString().padLeft(3, '0'));
      }

      // 4) Cualquier campo 'fecha' => hoy
      for (final f in widget.template.campos.where((f) => f.type == 'fecha')) {
        _setValueAndController(f.key, _isoToday());
      }

      if (mounted) setState(() {});
    } catch (_) {
      // no bloqueamos por error de autollenado
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_hydrateDefaultsOnce);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _uploadSignaturePng(
    Uint8List bytes,
    String uid,
    String docId,
    String key,
  ) async {
    final ref = FirebaseStorage.instance.ref().child(
      'formularios_firmas/$uid/$docId/$key.png',
    );
    await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
    return ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Sesión expirada.', color: Colors.red);
      return;
    }
    final uid = user.uid;

    setState(() => _saving = true);
    try {
      final fs = FirebaseFirestore.instance;
      final registros = fs.collection('formularios_registros');
      final newDoc = registros.doc(); // id auto
      final createdAt = FieldValue.serverTimestamp();

      // Subir firmas (si existen)
      final Map<String, dynamic> dataToSave = Map<String, dynamic>.from(
        _values,
      );
      for (final field in widget.template.campos) {
        if (field.type == 'firma') {
          final key = field.key;
          final val = _values[key];
          if (val is Map && val['pngBytes'] is Uint8List) {
            final url = await _uploadSignaturePng(
              val['pngBytes'] as Uint8List,
              uid,
              newDoc.id,
              key,
            );
            dataToSave[key] = {'url': url, 'at': FieldValue.serverTimestamp()};
          }
        }
      }

      // Detectar proyectoId para indexar
      String? proyectoIdForIndex;
      for (final k in ['proyecto', 'obra', 'equipo']) {
        final v = _values[k];
        if (v is Map && v['id'] is String) {
          proyectoIdForIndex = v['id'] as String;
          break;
        }
      }

      await newDoc.set({
        'templateId': widget.template.id,
        'templateNombre': widget.template.nombre,
        'uid': uid,
        'createdAt': createdAt,
        'proyectoId': proyectoIdForIndex ?? _myProyectoId,
        'data': dataToSave,
      }, SetOptions(merge: true));

      _snack('Formulario enviado ✅', color: Colors.green);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('No se pudo enviar: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- UI builders ----------
  Widget _buildField(FormFieldSpec f) {
    final key = f.key;

    // Autollenados/solo lectura
    if (key == 'acta_numero' || key == 'recibido_por' || key == 'cargo') {
      final c = _ctrlFor(key, initial: (_values[key] ?? '') as String);
      return _FieldCard(
        child: TextFormField(
          controller: c,
          enabled: false,
          readOnly: true,
          decoration: InputDecoration(
            labelText: key == 'acta_numero' ? 'N.º de acta (auto)' : f.label,
            helperText: key == 'acta_numero'
                ? 'Se asigna automáticamente'
                : 'Se llena automáticamente',
            border: const OutlineInputBorder(),
          ),
        ),
      );
    }

    // Campos especiales: usar dropdown de proyectos activos
    if (key == 'proyecto' || key == 'obra' || key == 'equipo') {
      final String? initial = (_values[key] is Map)
          ? (_values[key]['id'] as String?)
          : _myProyectoId;
      return _FieldCard(
        child: _ProyectoDropdownField(
          label: f.label,
          required: f.required,
          initialProyectoId: initial,
          onChanged: (id, nombre) {
            _values[key] = {'id': id, 'nombre': nombre};
          },
        ),
      );
    }

    switch (f.type) {
      case 'texto':
        final c = _ctrlFor(f.key, initial: (_values[key] ?? '') as String);
        return _FieldCard(
          child: TextFormField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Texto',
              border: OutlineInputBorder(),
            ).copyWith(labelText: f.label),
            validator: (v) => f.required && (v == null || v.trim().isEmpty)
                ? 'Requerido'
                : null,
            onChanged: (v) => _values[key] = v.trim(),
          ),
        );

      case 'numero':
        final c = _ctrlFor(f.key, initial: (_values[key]?.toString() ?? ''));
        return _FieldCard(
          child: TextFormField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Número',
              border: OutlineInputBorder(),
            ).copyWith(labelText: f.label),
            validator: (v) {
              if (!f.required && (v == null || v.isEmpty)) return null;
              final n = num.tryParse(v ?? '');
              return n == null ? 'Número inválido' : null;
            },
            onChanged: (v) => _values[key] = v,
          ),
        );

      case 'parrafo':
        final c = _ctrlFor(f.key, initial: (_values[key] ?? '') as String);
        return _FieldCard(
          child: TextFormField(
            controller: c,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              border: OutlineInputBorder(),
            ).copyWith(labelText: f.label),
            validator: (v) => f.required && (v == null || v.trim().isEmpty)
                ? 'Requerido'
                : null,
            onChanged: (v) => _values[key] = v.trim(),
          ),
        );

      case 'select':
        final opts = f.options;
        final current = _values[key] as String?;
        return _FieldCard(
          child: DropdownButtonFormField<String>(
            value: (current != null && current.isNotEmpty) ? current : null,
            items: opts
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              _values[key] = v;
              setState(() {}); // por si hay dependencias visuales
            },
            decoration: InputDecoration(
              labelText: f.label,
              border: const OutlineInputBorder(),
            ),
            validator: (v) =>
                f.required && (v == null || v.isEmpty) ? 'Requerido' : null,
          ),
        );

      case 'fecha':
        final currentText = (_values[key] ?? _isoToday()) as String;
        _values[key] = currentText; // asegurar valor
        return _FieldCard(
          child: _FechaHoyField(
            key: ValueKey('${key}_$currentText'),
            label: f.label,
            initialText: currentText,
            required: f.required,
            onChanged: (iso) => _values[key] = iso,
          ),
        );

      case 'firma':
        return _FieldCard(
          child: SignatureField(
            label: f.label,
            required: f.required,
            onChanged: (pngBytes) {
              _values[key] = {'pngBytes': pngBytes, 'ts': DateTime.now()};
            },
          ),
        );

      default:
        return _FieldCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(f.label),
            subtitle: const Text('Tipo de campo no soportado aún'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.template.campos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formulario'),
        backgroundColor: kCorpBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          ListView(
            children: [
              // Header con gradiente y resumen (full width)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1, -1),
                    end: Alignment(1, .2),
                    colors: [kCorpBlue, Color(0xFF3D8BFF)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.template.nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _pill(
                          '${fields.length} campo${fields.length == 1 ? '' : 's'}',
                        ),
                        _pill('Fecha: ${_isoToday()}'),
                      ],
                    ),
                  ],
                ),
              ),

              // Formulario centrado (responsive)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Form(
                    key: _formKey,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: fields.length,
                      itemBuilder: (_, i) => _buildField(fields[i]),
                    ),
                  ),
                ),
              ),

              // Botón Enviar (responsive) con loader pequeño
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCorpYellow,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _saving
                            ? Row(
                                key: const ValueKey('sending'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  // 👇 loader unificado, tamaño chico
                                  LoadingIndicator(size: 24),
                                  SizedBox(width: 8),
                                  Text(
                                    'Enviando…',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                key: const ValueKey('send'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.send),
                                  SizedBox(width: 8),
                                  Text(
                                    'Enviar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Overlay de proceso (mismo loader en todo lado)
          if (_saving)
            const PositionedFillOverlay(message: 'Guardando formulario…'),
        ],
      ),
    );
  }
}

class PositionedFillOverlay extends StatelessWidget {
  final String? message;
  const PositionedFillOverlay({super.key, this.message});
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: const Color(0x33000000),
          child: Center(
            child: LoadingIndicator(message: message ?? 'Procesando…'),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta visual para cada campo
class _FieldCard extends StatelessWidget {
  final Widget child;
  const _FieldCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: child,
    );
  }
}

/// Campo de fecha bloqueado al día de hoy (no pasado / no futuro)
class _FechaHoyField extends StatefulWidget {
  final String label;
  final String initialText; // ISO yyyy-MM-dd
  final bool required;
  final ValueChanged<String> onChanged;
  const _FechaHoyField({
    super.key,
    required this.label,
    required this.initialText,
    required this.required,
    required this.onChanged,
  });

  @override
  State<_FechaHoyField> createState() => _FechaHoyFieldState();
}

class _FechaHoyFieldState extends State<_FechaHoyField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void didUpdateWidget(covariant _FechaHoyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText) {
      _ctrl.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today,
      initialDate: today,
    );
    if (d == null) return;
    final iso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    _ctrl.text = iso;
    widget.onChanged(iso);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: 'Solo puede seleccionar el día de hoy',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(icon: const Icon(Icons.event), onPressed: _pick),
      ),
      validator: (v) =>
          widget.required && (v == null || v.isEmpty) ? 'Requerido' : null,
      onTap: _pick,
    );
  }
}

/// Dropdown dinámico de proyectos activos (colección 'proyectos': {nombre, activo}).
/// onChanged retorna (id, nombre); se espera que el caller lo guarde como {'id','nombre'}.
class _ProyectoDropdownField extends StatelessWidget {
  final String label;
  final bool required;
  final String? initialProyectoId;
  final void Function(String id, String nombre) onChanged;

  const _ProyectoDropdownField({
    required this.label,
    required this.required,
    required this.initialProyectoId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('proyectos')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // Deshabilitado y sin duplicar spinners
          return TextFormField(
            enabled: false,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              hintText: 'Cargando proyectos…',
            ),
          );
        }

        final docs =
            (snap.data?.docs ?? []).where((d) {
              final m = (d.data() as Map<String, dynamic>?) ?? {};
              final activo = m['activo'];
              return (activo == null) ||
                  (activo is bool && activo == true) ||
                  (activo is String &&
                      (activo.toLowerCase() == 'true' || activo == '1'));
            }).toList()..sort((a, b) {
              final ma = (a.data() as Map<String, dynamic>?) ?? {};
              final mb = (b.data() as Map<String, dynamic>?) ?? {};
              final na = (ma['nombre'] ?? a.id).toString();
              final nb = (mb['nombre'] ?? b.id).toString();
              return na.toLowerCase().compareTo(nb.toLowerCase());
            });

        if (docs.isEmpty) {
          return TextFormField(
            enabled: false,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              hintText: 'Sin proyectos disponibles',
            ),
          );
        }

        final items = docs.map((d) {
          final m = (d.data() as Map<String, dynamic>?) ?? {};
          final nombre = (m['nombre'] ?? d.id).toString();
          return DropdownMenuItem<String>(value: d.id, child: Text(nombre));
        }).toList();

        final validIds = docs.map((d) => d.id).toSet();
        final value =
            (initialProyectoId != null && validIds.contains(initialProyectoId))
            ? initialProyectoId
            : null;

        return DropdownButtonFormField<String>(
          value: value,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            final match = docs.firstWhere((d) => d.id == v);
            final nombre =
                ((match.data() as Map<String, dynamic>)['nombre'] ?? v)
                    .toString();
            onChanged(v, nombre);
          },
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            if (!required) return null;
            return (v == null || v.isEmpty) ? 'Requerido' : null;
          },
        );
      },
    );
  }
}

Widget _pill(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: .2,
      ),
    ),
  );
}
