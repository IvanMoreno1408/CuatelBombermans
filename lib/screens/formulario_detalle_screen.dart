import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/loading_indicator.dart';

// Paleta consistente con la otra vista
const _brandBlue = Color(0xFF0E4DA4);
const _brandBlueDark = Color(0xFF0A3A7B);
const _brandYellow = Color(0xFFFFC107);
const _surface = Color(0xFFF6F7FB);

class FormularioDetalleScreen extends StatelessWidget {
  final String docId;
  const FormularioDetalleScreen({super.key, required this.docId});

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance
        .collection('formularios_registros')
        .doc(docId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del envío'),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: _surface,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: LoadingIndicator(message: 'Cargando detalle…'),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Registro no encontrado'));
          }

          final m = snap.data!.data()!;
          final ts = (m['createdAt'] as Timestamp?)?.toDate();
          final fecha = ts == null
              ? '—'
              : '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year} '
                    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

          final templateNombre =
              (m['templateNombre'] ?? m['templateId'] ?? 'Formulario')
                  .toString();

          final templateId = (m['templateId'] as String?);
          final data = (m['data'] as Map?)?.cast<String, dynamic>() ?? {};

          // Nombre de contexto (Proyecto / Obra / Equipo) para el header
          final contextoNombre =
              (data['proyecto']?['nombre'] ??
                      data['obra']?['nombre'] ??
                      data['equipo']?['nombre'])
                  ?.toString();

          // Si no hay templateId, usamos fallback (orden por key bonita)
          if (templateId == null || templateId.isEmpty) {
            final entries = _orderedEntriesByPrettyKey(data);
            return _DetalleLista(
              header: _HeaderBlock(
                titulo: templateNombre,
                fecha: fecha,
                contexto: contextoNombre,
              ),
              entries: entries,
              labels: const {},
            );
          }

          // Si hay templateId, traemos la plantilla para labels y orden.
          final templateRef = FirebaseFirestore.instance
              .collection('formularios_templates')
              .doc(templateId);

          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: templateRef.get(),
            builder: (context, tmplSnap) {
              final campos =
                  (tmplSnap.data?.data()?['campos'] as List?) ?? const [];
              final labelByKey = <String, String>{};
              final orderedKeys = <String>[];

              for (final raw in campos) {
                if (raw is Map) {
                  final k = (raw['key'] ?? '').toString();
                  final l = _stripAutoTag((raw['label'] ?? k).toString());
                  if (k.isNotEmpty) {
                    orderedKeys.add(k);
                    labelByKey[k] = l;
                  }
                }
              }

              // Orden principal: orden de la plantilla; luego llaves restantes ordenadas
              final used = <String>{};
              final ordered = <MapEntry<String, dynamic>>[];
              for (final k in orderedKeys) {
                if (data.containsKey(k)) {
                  ordered.add(MapEntry(k, data[k]));
                  used.add(k);
                }
              }
              final leftovers =
                  data.entries.where((e) => !used.contains(e.key)).toList()
                    ..sort(
                      (a, b) =>
                          a.key.toLowerCase().compareTo(b.key.toLowerCase()),
                    );
              ordered.addAll(leftovers);

              return _DetalleLista(
                header: _HeaderBlock(
                  titulo: templateNombre,
                  fecha: fecha,
                  contexto: contextoNombre,
                ),
                entries: ordered,
                labels: labelByKey,
              );
            },
          );
        },
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  final String titulo;
  final String fecha;
  final String? contexto; // Proyecto/Obra/Equipo (nombre)

  const _HeaderBlock({
    required this.titulo,
    required this.fecha,
    required this.contexto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_brandBlue, _brandBlueDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pillYellow('Fecha: $fecha'),
              if (contexto != null && contexto!.trim().isNotEmpty)
                _pillWhite(contexto!),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetalleLista extends StatelessWidget {
  final _HeaderBlock header;
  final List<MapEntry<String, dynamic>> entries;
  final Map<String, String> labels;

  const _DetalleLista({
    required this.header,
    required this.entries,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        header,
        const SizedBox(height: 8),
        ...entries.map((e) {
          final display = _stripAutoTag(labels[e.key] ?? _prettifyKey(e.key));
          return _FieldView(label: display, value: e.value);
        }),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _FieldView extends StatelessWidget {
  final String label;
  final dynamic value;

  const _FieldView({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    Widget child;

    // Firma: {url, at}
    if (value is Map && value['url'] is String) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              value['url'] as String,
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
        ],
      );
    }
    // Relación {id, nombre} → mostramos SOLO el nombre (sin id)
    else if (value is Map && value['nombre'] != null) {
      final nombre = value['nombre'];
      child = ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$nombre'),
      );
    }
    // Texto / número / boolean / fecha simple
    else if (value is String || value is num || value is bool) {
      final display = value is bool
          ? (value ? 'Sí' : 'No')
          : _maybeFormatIsoDate(value.toString());
      child = ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(display),
      );
    }
    // Otro tipo (map/array)
    else {
      child = ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(value?.toString() ?? '—'),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8EEF8)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ----- Pills (chips) del header -----

Widget _pillYellow(String text) {
  return Container(
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
    child: Text(
      text,
      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
    ),
  );
}

Widget _pillWhite(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white24),
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
        const Icon(Icons.place_outlined, size: 16),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

/// ---------- Helpers de presentación ----------

String _prettifyKey(String raw) {
  final cleaned = raw.replaceAll('_', ' ').trim();
  final parts = cleaned.split(RegExp(r'\s+'));
  return parts
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _maybeFormatIsoDate(String s) {
  // yyyy-MM-dd → dd/MM/yyyy si encaja
  final re = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  final m = re.firstMatch(s);
  if (m != null) {
    final y = m.group(1)!;
    final mo = m.group(2)!;
    final d = m.group(3)!;
    return '$d/$mo/$y';
  }
  return s;
}

List<MapEntry<String, dynamic>> _orderedEntriesByPrettyKey(
  Map<String, dynamic> data,
) {
  final list = data.entries.toList();
  list.sort(
    (a, b) => _prettifyKey(
      a.key,
    ).toLowerCase().compareTo(_prettifyKey(b.key).toLowerCase()),
  );
  return list;
}

String _stripAutoTag(String s) {
  // elimina "(auto)" (may/min) y espacios adyacentes
  return s.replaceAll(RegExp(r'\s*\(auto\)', caseSensitive: false), '').trim();
}
