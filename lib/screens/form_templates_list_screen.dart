// lib/screens/form_templates_list_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../models/form_template.dart';
import 'formulario_lleno_screen.dart';
import 'formularios_enviados_screen.dart';

const String kTemplatesCollection = 'formularios_templates';

// Paleta corporativa
const _brandBlue = Color(0xFF0E4DA4);
const _brandBlueDark = Color(0xFF0A3A7B);
const _brandYellow = Color(0xFFFFC107);
const _brandYellowSoft = Color(0xFFFFECB3);
const _surface = Colors.white;

// Lottie loading
const _loadingLottiePath = 'lottie/loading.json';

class FormTemplatesListScreen extends StatelessWidget {
  const FormTemplatesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Stream<QuerySnapshot<Map<String, dynamic>>> stream = FirebaseFirestore
        .instance
        .collection(kTemplatesCollection)
        .orderBy('nombre')
        .snapshots();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_brandBlue, _brandBlueDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const _Header(),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: stream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: Lottie.asset(
                            _loadingLottiePath,
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
                            'Error: ${snap.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No hay formularios configurados.'),
                        );
                      }

                      final templates = docs
                          .map((d) => FormTemplate.fromMap(d.id, d.data()))
                          .toList();

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: templates.length,
                        itemBuilder: (context, i) {
                          final t = templates[i];
                          return _TemplateCard(
                            name: t.nombre,
                            version: t.version,
                            fieldCount: t.campos.length,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      FormularioLlenoScreen(template: t),
                                ),
                              );
                            },
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
}

// =================== Header ===================

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.assignment_outlined,
                color: _brandYellow,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'Formularios',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),

              // 👇 Solo la píldora amarilla de historial
              const _HistoryPill(),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: _brandYellow, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selecciona un formulario para llenarlo en sitio.',
                    style: TextStyle(color: Colors.white, height: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Píldora amarilla que navega al historial si el usuario es admin o lider.
class _HistoryPill extends StatelessWidget {
  const _HistoryPill();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FormulariosEnviadosScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _brandYellow,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.outbox, size: 16, color: Colors.black),
            SizedBox(width: 6),
            Text(
              'Historial',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================== Tarjeta ===================

class _TemplateCard extends StatelessWidget {
  final String name;
  final int version;
  final int fieldCount;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.name,
    required this.version,
    required this.fieldCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final versionChip = Chip(
      label: Text(
        'v$version',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      backgroundColor: _brandYellowSoft,
      side: const BorderSide(color: _brandYellow),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    );

    final fieldsChip = Chip(
      label: Text('$fieldCount campos'),
      backgroundColor: Colors.blue.shade50,
      side: BorderSide(color: Colors.blue.shade200),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icono principal
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _brandBlue.withOpacity(0.28)),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: _brandBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),

              // Texto + chips
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: -6,
                      children: [versionChip, fieldsChip],
                    ),
                  ],
                ),
              ),

              // CTA
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Llenar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
