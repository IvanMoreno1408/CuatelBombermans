// lib/models/form_template.dart
class FormFieldSpec {
  final String key; // ej: "firma_responsable"
  final String type; // 'texto' | 'numero' | 'select' | 'firma' | ...
  final String label; // ej: "Firma responsable"
  final bool required;
  final List<String> options;

  FormFieldSpec({
    required this.key,
    required this.type,
    required this.label,
    this.required = false,
    this.options = const [],
  });

  factory FormFieldSpec.fromMap(Map<String, dynamic> m) {
    return FormFieldSpec(
      key: m['key'] as String,
      type: m['type'] as String,
      label: m['label'] as String,
      required: (m['required'] ?? false) as bool,
      options: ((m['options'] ?? []) as List).map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'type': type,
    'label': label,
    'required': required,
    if (options.isNotEmpty) 'options': options,
  };
}

class FormTemplate {
  final String id;
  final String nombre;
  final int version;
  final List<String> rolesPermitidos;
  final List<FormFieldSpec> campos;

  FormTemplate({
    required this.id,
    required this.nombre,
    required this.version,
    required this.rolesPermitidos,
    required this.campos,
  });

  factory FormTemplate.fromMap(String id, Map<String, dynamic> m) {
    final rawCampos = (m['campos'] ?? m['fields'] ?? []) as List;
    final campos = rawCampos
        .where((e) => e is Map)
        .map((e) => FormFieldSpec.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    return FormTemplate(
      id: id,
      nombre: (m['nombre'] ?? 'Formulario') as String,
      version: (m['version'] ?? 1) as int,
      rolesPermitidos: ((m['rolesPermitidos'] ?? []) as List)
          .map((e) => e.toString())
          .toList(),
      campos: campos,
    );
  }

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'version': version,
    if (rolesPermitidos.isNotEmpty) 'rolesPermitidos': rolesPermitidos,
    'campos': campos.map((c) => c.toMap()).toList(),
  };
}
