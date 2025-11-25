// lib/screens/admin_reto_form_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/loading_indicator.dart'; // loader unificado

// Paleta corporativa (igual que en FormularioLlenoScreen)
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);

class AdminRetoFormScreen extends StatefulWidget {
  final String? retoId;
  final Map<String, dynamic>? initialData;
  const AdminRetoFormScreen({super.key, this.retoId, this.initialData});

  @override
  State<AdminRetoFormScreen> createState() => _AdminRetoFormScreenState();
}

class _AdminRetoFormScreenState extends State<AdminRetoFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _tituloCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _xpCtrl = TextEditingController(text: '30');
  final _ordenCtrl = TextEditingController(text: '1');
  final _formLinkCtrl = TextEditingController();
  final _checkOptionsCtrl = TextEditingController(); // coma-separado

  bool _activa = true;
  bool _requirePhoto = false;
  bool _requireNote = false;
  bool _ratingEnabled = false; // Bueno/Regular/Malo
  bool _cameraOnly = false; // obliga a cámara
  bool _projectScoped = true; // evidencia atada a proyecto
  bool _saving = false;

  // general | entry | exit | paro_event | weekly_report | form_link | streak_bomba | streak_grua
  String _type = 'general';

  // '', 'bomberman', 'gruaman'  ('' = todos)
  String _subrol = '';

  @override
  void initState() {
    super.initState();
    final m = widget.initialData ?? {};
    if (m.isNotEmpty) {
      _tituloCtrl.text = (m['titulo'] ?? '') as String;
      _descCtrl.text = (m['descripcion'] ?? '') as String;
      _xpCtrl.text = ((m['xp'] ?? 30) as int).toString();
      _ordenCtrl.text = ((m['orden'] ?? 1) as int).toString();
      _activa = (m['activa'] ?? true) as bool;

      _requirePhoto =
          (m['requirePhoto'] ?? m['requiresPhoto'] ?? false) as bool;
      _requireNote = (m['requireNote'] ?? m['requiresNote'] ?? false) as bool;
      _ratingEnabled =
          (m['ratingEnabled'] ?? m['requiresCheck'] ?? false) as bool;
      _cameraOnly = (m['cameraOnly'] ?? false) as bool;
      _projectScoped = (m['projectScoped'] ?? true) as bool;

      _type = (m['type'] ?? m['tipo'] ?? 'general') as String;
      _formLinkCtrl.text = (m['formLink'] ?? '') as String;

      _subrol = (m['subrol'] ?? '') as String;

      // checkOptions (si vienen)
      final rawOpts = m['checkOptions'];
      if (rawOpts is List) {
        _checkOptionsCtrl.text = rawOpts.whereType<String>().join(', ');
      }
    }
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    _xpCtrl.dispose();
    _ordenCtrl.dispose();
    _formLinkCtrl.dispose();
    _checkOptionsCtrl.dispose();
    super.dispose();
  }

  void _snack(String m, {Color color = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  List<String>? _parseCheckOptions() {
    final raw = _checkOptionsCtrl.text.trim();
    if (raw.isEmpty) return null;
    final list = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return list.isEmpty ? null : list;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final opts = _parseCheckOptions();

    final data = <String, dynamic>{
      'titulo': _tituloCtrl.text.trim(),
      'descripcion': _descCtrl.text.trim(),
      'xp': int.tryParse(_xpCtrl.text.trim()) ?? 0,
      'orden': int.tryParse(_ordenCtrl.text.trim()) ?? 1,
      'activa': _activa,

      // flags (con duplicados para retrocompatibilidad)
      'requirePhoto': _requirePhoto,
      'requiresPhoto': _requirePhoto,
      'requireNote': _requireNote,
      'requiresNote': _requireNote,
      'ratingEnabled': _ratingEnabled,
      'requiresCheck': _ratingEnabled,
      'cameraOnly': _cameraOnly,
      'projectScoped': _projectScoped,

      // tipo (duplicado)
      'type': _type,
      'tipo': _type,

      // subrol ('' = todos)
      'subrol': _subrol,

      if (_type == 'form_link') 'formLink': _formLinkCtrl.text.trim(),
      if (opts != null) 'checkOptions': opts,

      'updatedAt': FieldValue.serverTimestamp(),
    };

    setState(() => _saving = true);
    try {
      final retos = FirebaseFirestore.instance.collection('retos');
      if (widget.retoId == null) {
        await retos.add({...data, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await retos.doc(widget.retoId!).set(data, SetOptions(merge: true));
      }
      _snack('Reto guardado ✅', color: Colors.green);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _snack('No se pudo guardar', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _pillTipo() {
    switch (_type) {
      case 'entry':
        return 'Entrada';
      case 'exit':
        return 'Salida';
      case 'paro_event':
        return 'PARO';
      case 'weekly_report':
        return 'Reporte semanal';
      case 'form_link':
        return 'Abrir formulario';
      case 'streak_bomba':
        return 'Racha bomba';
      case 'streak_grua':
        return 'Racha grúa';
      default:
        return 'General';
    }
  }

  String _pillSubrol() {
    switch (_subrol) {
      case 'bomberman':
        return 'Bomberman';
      case 'gruaman':
        return 'Gruaman';
      default:
        return 'Todos';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.retoId != null;
    final isFormLink = _type == 'form_link';

    // Construyo los bloques de forma declarativa para evitar índices frágiles
    final List<Widget> blocks = [
      // Título
      _FieldCard(
        child: TextFormField(
          controller: _tituloCtrl,
          decoration: const InputDecoration(
            labelText: 'Título',
            helperText: 'Nombre corto y claro del reto',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          onChanged: (_) => setState(() {}),
        ),
      ),

      // Descripción
      _FieldCard(
        child: TextFormField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            border: OutlineInputBorder(),
          ),
        ),
      ),

      // XP / Orden
      _FieldCard(
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _xpCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'XP',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _ordenCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Orden',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),

      // Activo
      _FieldCard(
        child: SwitchListTile(
          title: const Text('Activo'),
          value: _activa,
          onChanged: (v) => setState(() => _activa = v),
          contentPadding: EdgeInsets.zero,
        ),
      ),

      // Tipo
      _FieldCard(
        child: DropdownButtonFormField<String>(
          value: _type,
          items: const [
            DropdownMenuItem(value: 'general', child: Text('General')),
            DropdownMenuItem(
              value: 'entry',
              child: Text('Entrada (foto cámara)'),
            ),
            DropdownMenuItem(
              value: 'exit',
              child: Text('Salida (foto cámara)'),
            ),
            DropdownMenuItem(
              value: 'paro_event',
              child: Text('Reporte de PARO'),
            ),
            DropdownMenuItem(
              value: 'weekly_report',
              child: Text('Reporte semanal'),
            ),
            DropdownMenuItem(value: 'streak_bomba', child: Text('Racha bomba')),
            DropdownMenuItem(value: 'streak_grua', child: Text('Racha grúa')),
            DropdownMenuItem(
              value: 'form_link',
              child: Text('Abrir Formulario (plantilla)'),
            ),
          ],
          onChanged: (v) => setState(() => _type = v ?? 'general'),
          decoration: const InputDecoration(
            labelText: 'Tipo de reto',
            border: OutlineInputBorder(),
          ),
        ),
      ),

      // Subrol
      _FieldCard(
        child: DropdownButtonFormField<String>(
          value: _subrol,
          items: const [
            DropdownMenuItem(value: '', child: Text('Todos')),
            DropdownMenuItem(value: 'bomberman', child: Text('Bomberman')),
            DropdownMenuItem(value: 'gruaman', child: Text('Gruaman')),
          ],
          onChanged: (v) => setState(() => _subrol = v ?? ''),
          decoration: const InputDecoration(
            labelText: 'Subrol objetivo',
            border: OutlineInputBorder(),
          ),
        ),
      ),

      // Flags de evidencia
      _FieldCard(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Requiere foto (evidencia)'),
              value: _requirePhoto,
              onChanged: (v) => setState(() => _requirePhoto = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Sólo cámara (sin galería)'),
              subtitle: const Text('Útil para entrada/salida'),
              value: _cameraOnly,
              onChanged: (v) => setState(() => _cameraOnly = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Requiere reseña/observación'),
              value: _requireNote,
              onChanged: (v) => setState(() => _requireNote = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Habilitar rating (Bueno/Regular/Malo)'),
              value: _ratingEnabled,
              onChanged: (v) => setState(() => _ratingEnabled = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Evidencia atada a proyecto'),
              subtitle: const Text('Guarda proyectoId del usuario'),
              value: _projectScoped,
              onChanged: (v) => setState(() => _projectScoped = v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),

      // CheckOptions opcional (coma-separado)
      _FieldCard(
        child: TextFormField(
          controller: _checkOptionsCtrl,
          decoration: const InputDecoration(
            labelText: 'CheckOptions (opcional)',
            helperText:
                'Escribe opciones separadas por comas. Ej: "Operativa todo el día, Parada"',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    ];

    if (isFormLink) {
      blocks.insert(
        6, // justo después de Subrol / antes de flags
        _FieldCard(
          child: TextFormField(
            controller: _formLinkCtrl,
            decoration: const InputDecoration(
              labelText: 'ID de plantilla (form_templates)',
              helperText: 'ID de la plantilla a abrir',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (_type != 'form_link') return null;
              if (v == null || v.trim().isEmpty) {
                return 'Requerido para "Abrir Formulario"';
              }
              return null;
            },
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar reto' : 'Crear reto'),
        backgroundColor: kCorpBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          ListView(
            children: [
              // Header con gradiente y resumen (pills)
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
                      isEditing ? 'Editar reto' : 'Nuevo reto',
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
                        _pill(_pillTipo()),
                        _pill('Subrol: ${_pillSubrol()}'),
                        _pill(_activa ? 'Activo' : 'Inactivo'),
                        _pill('XP: ${_xpCtrl.text}'),
                        _pill('Orden: ${_ordenCtrl.text}'),
                      ],
                    ),
                  ],
                ),
              ),

              // Formulario
              Form(
                key: _formKey,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: blocks.length,
                  itemBuilder: (_, i) => blocks[i],
                ),
              ),

              // Botón Guardar al final
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCorpYellow,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_saving)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: LoadingIndicator(size: 28)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta visual reutilizable (igual estilo que en FormularioLlenoScreen)
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

/// Pill visual (igual helper que el otro screen)
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
