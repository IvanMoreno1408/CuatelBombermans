// lib/screens/retos_screen.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';

import 'profile_screen.dart';
import '../widgets/loading_indicator.dart'; // 👈 Loader consistente en toda la app

// Paleta corporativa (azul/amarillo, estilo vibrante)
const _brandBlue = Color(0xFF0E4DA4);
const _brandBlueDark = Color(0xFF0A3A7B);
const _brandYellow = Color(0xFFFFC107);
const _brandYellowSoft = Color(0xFFFFECB3);
const _surface = Colors.white;

// ---- STREAK TIERS ----
enum _StreakTier { t3, t10, t30, t100, t200 }

_StreakTier _tierFor(int s) {
  if (s >= 200) return _StreakTier.t200;
  if (s >= 100) return _StreakTier.t100;
  if (s >= 30) return _StreakTier.t30;
  if (s >= 10) return _StreakTier.t10;
  return _StreakTier.t3; // 1–9
}

String _lottieForTier(_StreakTier t) {
  switch (t) {
    case _StreakTier.t200:
      return 'lottie/Flameanimation200days.json';
    case _StreakTier.t100:
      return 'lottie/Flameanimation100days.json';
    case _StreakTier.t30:
      return 'lottie/Flameanimation30days.json';
    case _StreakTier.t10:
      return 'lottie/Flameanimation10days.json';
    case _StreakTier.t3:
      return 'lottie/Flameanimation3days.json';
  }
}

Color _flameColorForTier(_StreakTier t) {
  switch (t) {
    case _StreakTier.t200:
      return const Color(0xFF8E5CF6); // violeta
    case _StreakTier.t100:
      return const Color(0xFFFF5BBE); // fucsia
    case _StreakTier.t30:
      return const Color(0xFFFF6A5B); // coral
    case _StreakTier.t10:
      return const Color(0xFFFF8C3A); // naranja
    case _StreakTier.t3:
      return _brandYellow; // amarillo
  }
}

class RetosScreen extends StatefulWidget {
  const RetosScreen({super.key});

  @override
  State<RetosScreen> createState() => _RetosScreenState();
}

class _RetosScreenState extends State<RetosScreen> {
  final _auth = FirebaseAuth.instance;
  final _picker = ImagePicker();
  bool _working = false;

  /// Mostrar animación (por tier) cuando mantiene o inicia racha
  bool _showStreakAnim = false;
  String? _streakAnimPath;

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  void _snack(String msg, {Color color = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _ensureStreaksUpToDate();
  }

  // ====== SUBIR FOTO A STORAGE ======
  Future<String?> _uploadPhoto({
    required String uid,
    required String doneId,
    required File file,
  }) async {
    final ref = FirebaseStorage.instance.ref().child(
      'evidencias/$uid/$doneId.jpg',
    );
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  // ====== RESET DE RACHAS SI AYER/HOY NO SE CUMPLIÓ ======
  bool _olderThanYesterday(String? lastKey) {
    if (lastKey == null || lastKey.isEmpty) return false;
    final now = DateTime.now();
    final hoy = _dateKey(now);
    final ayer = _dateKey(
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
    );
    // Si no fue ni hoy ni ayer => se pierde la racha
    return !(lastKey == hoy || lastKey == ayer);
  }

  Future<void> _ensureStreaksUpToDate() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final fs = FirebaseFirestore.instance;
    final ref = fs.collection('usuarios').doc(user.uid);

    try {
      final snap = await ref.get();
      final data = snap.data() ?? {};

      final gS = (data['streak'] ?? 0) as int;
      final gL = data['streakLastDate'] as String?;
      final bS = (data['streak_bomba'] ?? 0) as int;
      final bL = data['streakBombaLastDate'] as String?;
      final mS = (data['streak_grua'] ?? 0) as int;
      final mL = data['streakGruaLastDate'] as String?;

      final patch = <String, dynamic>{};

      if (gS > 0 && _olderThanYesterday(gL)) patch['streak'] = 0;
      if (bS > 0 && _olderThanYesterday(bL)) patch['streak_bomba'] = 0;
      if (mS > 0 && _olderThanYesterday(mL)) patch['streak_grua'] = 0;

      if (patch.isNotEmpty) {
        patch['updatedAt'] = FieldValue.serverTimestamp();
        await ref.set(patch, SetOptions(merge: true));
      }
    } catch (_) {
      // Silencioso
    }
  }

  // ====== MODAL DE EVIDENCIA ======
  Future<Map<String, dynamic>?> _openEvidenceForm({
    required Map<String, dynamic> reto,
  }) async {
    final requiresPhoto =
        (reto['requiresPhoto'] ?? reto['requirePhoto'] ?? false) as bool;
    final requiresNote =
        (reto['requiresNote'] ?? reto['requireNote'] ?? false) as bool;
    final requiresCheck =
        (reto['requiresCheck'] ?? reto['ratingEnabled'] ?? false) as bool;
    final cameraOnly = (reto['cameraOnly'] ?? false) as bool;
    final tipo = (reto['tipo'] ?? reto['type'] ?? 'general') as String;

    // Default checkOptions si es “sin paro”
    final defaultCheck = (tipo == 'streak_bomba' || tipo == 'streak_grua')
        ? const ['Operativa todo el día', 'Parada']
        : const ['Bueno', 'Regular', 'Malo'];
    final checkOptions = ((reto['checkOptions'] ?? defaultCheck) as List)
        .cast<String>();

    File? pickedFile;
    String? nota;
    String? checkEstado;
    String? checkComentario;

    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.40,
          maxChildSize: 0.90,
          builder: (ctx, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: StatefulBuilder(
                builder: (ctx, setS) {
                  Future<void> pickImage() async {
                    if (cameraOnly) {
                      final x = await _picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 85,
                      );
                      if (x != null) {
                        pickedFile = File(x.path);
                        setS(() {});
                      }
                      return;
                    }

                    final source = await showModalBottomSheet<ImageSource?>(
                      context: ctx,
                      backgroundColor: Colors.transparent,
                      builder: (_) => SafeArea(
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(
                                  Icons.photo_camera,
                                  color: _brandBlue,
                                ),
                                title: const Text('Cámara'),
                                onTap: () =>
                                    Navigator.pop(ctx, ImageSource.camera),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(
                                  Icons.photo_library,
                                  color: _brandBlue,
                                ),
                                title: const Text('Galería'),
                                onTap: () =>
                                    Navigator.pop(ctx, ImageSource.gallery),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (source == null) return;
                    final x = await _picker.pickImage(
                      source: source,
                      imageQuality: 85,
                    );
                    if (x != null) {
                      pickedFile = File(x.path);
                      setS(() {});
                    }
                  }

                  Future<void> showPreview(File file) async {
                    await showDialog(
                      context: context, // usa el navigator correcto
                      barrierDismissible: true, // permite cerrar tocando fuera
                      barrierColor: Colors.black87,
                      useSafeArea: true,
                      builder: (previewCtx) => Dialog(
                        insetPadding: const EdgeInsets.all(12),
                        backgroundColor: Colors.black,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: InteractiveViewer(
                                minScale: 0.5,
                                maxScale: 4,
                                child: Image.file(
                                  file,
                                  fit: BoxFit.contain,
                                  // opcional: reduce costo de decodificación
                                  filterQuality: FilterQuality.low,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                onPressed: () => Navigator.of(
                                  previewCtx,
                                ).pop(), // 👈 usa el contexto del diálogo
                                tooltip: 'Cerrar',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  void submit() {
                    if (requiresPhoto && pickedFile == null) {
                      _snack('Debes adjuntar una foto.', color: Colors.red);
                      return;
                    }
                    if (requiresNote &&
                        (nota == null || nota!.trim().isEmpty)) {
                      _snack('Debes escribir una nota.', color: Colors.red);
                      return;
                    }
                    if (requiresCheck &&
                        (checkEstado == null || checkEstado!.isEmpty)) {
                      _snack('Selecciona una opción.', color: Colors.red);
                      return;
                    }
                    Navigator.pop<Map<String, dynamic>>(ctx, {
                      'tipo': tipo,
                      'pickedFile': pickedFile,
                      'nota': (nota ?? '').trim(),
                      'checkEstado': checkEstado,
                      'checkComentario': (checkComentario ?? '').trim(),
                    });
                  }

                  return SingleChildScrollView(
                    controller: scrollCtrl,
                    child: Column(
                      children: [
                        Container(
                          height: 5,
                          width: 48,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Text(
                          'Evidencia requerida',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (requiresPhoto) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Foto (obligatoria)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // ======= Botón seleccionar y nombre de archivo =======
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: pickImage,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: Text(
                                  cameraOnly ? 'Tomar foto' : 'Elegir foto',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _brandBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (pickedFile != null)
                                Expanded(
                                  child: Text(
                                    pickedFile!.path.split('/').last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),

                          // ======= PREVIEW EN EL MISMO MODAL =======
                          if (pickedFile != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Image.file(
                                      pickedFile!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: Row(
                                      children: [
                                        // Ver
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              showPreview(pickedFile!),
                                          icon: const Icon(Icons.fullscreen),
                                          label: const Text('Ver'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.black
                                                .withOpacity(0.55),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Quitar
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            pickedFile = null;
                                            setS(() {});
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Quitar'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red
                                                .withOpacity(0.85),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),
                        ],

                        if (requiresNote) ...[
                          TextFormField(
                            decoration: _field(
                              'Nota / observación (obligatoria)',
                            ),
                            maxLines: 3,
                            onChanged: (v) => nota = v,
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (requiresCheck) ...[
                          DropdownButtonFormField<String>(
                            value: checkEstado,
                            items: checkOptions
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(o),
                                  ),
                                )
                                .toList(),
                            decoration: _field('Selecciona'),
                            onChanged: (v) => setS(() => checkEstado = v),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            decoration: _field('Comentario (opcional)'),
                            maxLines: 2,
                            onChanged: (v) => checkComentario = v,
                          ),
                          const SizedBox(height: 12),
                        ],

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: submit,
                            icon: const Icon(Icons.check),
                            label: const Text('Enviar evidencia'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brandYellow,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  static InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _brandBlue, width: 2),
    ),
  );

  // ====== COMPLETAR RETO (con evidencia) ======
  Future<void> _completarRetoConEvidencia(
    String retoId,
    Map<String, dynamic> reto,
  ) async {
    if (_working) return;
    setState(() => _working = true);

    bool keptGeneralStreakToday = false;
    bool startedGeneralStreakToday = false;
    int _newGeneralVal = 0; // para decidir animación

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _snack('Sesión expirada. Inicia sesión de nuevo.', color: Colors.red);
        setState(() => _working = false);
        return;
      }
      final fs = FirebaseFirestore.instance;
      final uid = user.uid;

      // 1) Evidencia via modal
      final evidence = await _openEvidenceForm(reto: reto);
      if (evidence == null) {
        setState(() => _working = false);
        return; // cancelado
      }

      final tipo = (evidence['tipo'] ?? 'general') as String;
      final File? pickedFile = evidence['pickedFile'] as File?;
      final String? nota = (evidence['nota'] as String?)?.trim();
      final String? checkEstado = evidence['checkEstado'] as String?;
      final String? checkComentario = (evidence['checkComentario'] as String?)
          ?.trim();

      // 2) Subir foto (si hay)
      final doneId = '${_todayKey}_$retoId';
      String? imageUrl;
      if (pickedFile != null) {
        try {
          imageUrl = await _uploadPhoto(
            uid: uid,
            doneId: doneId,
            file: pickedFile,
          );
        } on FirebaseException catch (e) {
          _snack('No se pudo subir la foto: ${e.message}', color: Colors.red);
          setState(() => _working = false);
          return;
        } catch (_) {
          _snack('No se pudo subir la foto.', color: Colors.red);
          setState(() => _working = false);
          return;
        }
      }

      // 3) Guardar tarea + XP + RACHAS (transacción)
      final userRef = fs.collection('usuarios').doc(uid);
      final doneRef = userRef.collection('tareasDiarias').doc(doneId);

      await fs.runTransaction((tx) async {
        final already = await tx.get(doneRef);
        if (already.exists) {
          throw Exception('YA_COMPLETADO');
        }

        final userSnap = await tx.get(userRef);
        final userData = userSnap.data() ?? <String, dynamic>{};
        final xpActual = (userData['xp'] ?? 0) as int;
        final xpReto = (reto['xp'] ?? 0) as int;
        final proyectoId = userData['proyectoId'];

        final now = DateTime.now();
        final hoyKey = _dateKey(now);
        final ayerKey = _dateKey(
          DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 1)),
        );

        // normalizar respuesta
        String norm(String? s) {
          if (s == null) return '';
          final lower = s.toLowerCase().trim();
          const from = 'áéíóúüÁÉÍÓÚÜ';
          const to = 'aeiouuAEIOUU';
          var out = lower;
          for (var i = 0; i < from.length; i++) {
            out = out.replaceAll(from[i], to[i]);
          }
          return out;
        }

        final okSet = <String>{
          'ok (no paro)',
          'operativa',
          'operativa todo el dia',
          'operativa todo el día',
          'sin paro',
          'bueno',
        };
        final isOkSinParo = okSet.contains(norm(checkEstado));

        // Guardar evidencia
        final payload = <String, dynamic>{
          'retoId': retoId,
          'titulo': reto['titulo'],
          'xp': xpReto,
          'fechaClave': _todayKey,
          'doneAt': FieldValue.serverTimestamp(),
          'tipo': tipo,
          'proyectoId': proyectoId,
          if (nota != null && nota.isNotEmpty) 'nota': nota,
          if (imageUrl != null) 'imageUrl': imageUrl,
          if (checkEstado != null) 'checkEstado': checkEstado,
          if (checkComentario != null && checkComentario.isNotEmpty)
            'checkComentario': checkComentario,
        };
        tx.set(doneRef, payload);

        // XP / Nivel
        final nuevoXp = xpActual + xpReto;
        final nuevoNivel = 1 + (nuevoXp ~/ 1000);

        // Racha general
        final curGeneral = (userData['streak'] ?? 0) as int;
        final lastGeneral = (userData['streakLastDate'] as String?);

        keptGeneralStreakToday = (lastGeneral == ayerKey);

        int newGeneral;
        if (lastGeneral == hoyKey) {
          newGeneral = curGeneral;
        } else if (lastGeneral == ayerKey) {
          newGeneral = curGeneral + 1;
        } else {
          newGeneral = 1;
        }
        _newGeneralVal = newGeneral;
        startedGeneralStreakToday =
            (lastGeneral == null ||
                (lastGeneral != hoyKey && lastGeneral != ayerKey)) &&
            newGeneral == 1;

        final patchUser = <String, dynamic>{
          'xp': nuevoXp,
          'nivel': nuevoNivel,
          'streak': newGeneral,
          'streakLastDate': hoyKey,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Racha grúa
        if (tipo == 'streak_grua' && checkEstado != null) {
          final curG = (userData['streak_grua'] ?? 0) as int;
          final lastG = (userData['streakGruaLastDate'] as String?);
          if (isOkSinParo) {
            final next = (lastG == ayerKey)
                ? (curG + 1)
                : (lastG == hoyKey ? curG : 1);
            patchUser['streak_grua'] = next;
            patchUser['streakGruaLastDate'] = hoyKey;
          } else {
            patchUser['streak_grua'] = 0;
            patchUser['streakGruaLastDate'] = hoyKey;
          }
        }

        // Racha bomba
        if (tipo == 'streak_bomba' && checkEstado != null) {
          final curB = (userData['streak_bomba'] ?? 0) as int;
          final lastB = (userData['streakBombaLastDate'] as String?);
          if (isOkSinParo) {
            final next = (lastB == ayerKey)
                ? (curB + 1)
                : (lastB == hoyKey ? curB : 1);
            patchUser['streak_bomba'] = next;
            patchUser['streakBombaLastDate'] = hoyKey;
          } else {
            patchUser['streak_bomba'] = 0;
            patchUser['streakBombaLastDate'] = hoyKey;
          }
        }

        tx.set(userRef, patchUser, SetOptions(merge: true));
      });

      _snack('✅ ¡Reto completado! +${reto['xp']} XP', color: Colors.green);

      // --- Animación por tier (si mantiene o empieza racha) ---
      final shouldAnimate = keptGeneralStreakToday || startedGeneralStreakToday;
      if (shouldAnimate && mounted) {
        final tier = _tierFor(_newGeneralVal);
        setState(() {
          _streakAnimPath = _lottieForTier(tier);
          _showStreakAnim = true;
        });
        // fallback por si onLoaded no dispara
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showStreakAnim = false);
        });
      }
    } catch (e) {
      if (e.toString().contains('YA_COMPLETADO')) {
        _snack('Ya completaste este reto hoy.', color: Colors.orange);
      } else {
        _snack('No se pudo completar el reto.', color: Colors.red);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      // Fondo con gradiente azul → azul oscuro
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_brandBlue, _brandBlueDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // ======= HEADER =======
                  if (user != null)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('usuarios')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, meSnap) {
                        if (meSnap.connectionState == ConnectionState.waiting) {
                          return const _HeaderSkeleton(); // 👈 skeleton en lugar de loader
                        }
                        final me = meSnap.data?.data() ?? {};
                        final xp = (me['xp'] ?? 0) as int;
                        final nivel = (me['nivel'] ?? 1) as int;
                        final streak = (me['streak'] ?? 0) as int;
                        return _Header(xp: xp, nivel: nivel, streak: streak);
                      },
                    )
                  else
                    const _HeaderSkeleton(),

                  // ======= CONTENIDO =======
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: _RetosList(
                        todayKey: _todayKey,
                        onCompletar: _completarRetoConEvidencia,
                        working: _working,
                      ),
                    ),
                  ),
                ],
              ),

              // Overlay "trabajando"
              if (_working)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      color: Colors.black26,
                      child: const Center(
                        child: LoadingIndicator(message: 'Procesando…'),
                      ),
                    ),
                  ),
                ),

              // Overlay Lottie cuando se mantiene/empieza racha (por tier)
              if (_showStreakAnim && _streakAnimPath != null)
                Positioned.fill(
                  child: Container(
                    color: Colors.black45,
                    child: Center(
                      child: Lottie.asset(
                        _streakAnimPath!,
                        repeat: false,
                        onLoaded: (composition) {
                          // Cierra al terminar exactamente la duración del JSON
                          Future.delayed(composition.duration, () {
                            if (mounted) {
                              setState(() => _showStreakAnim = false);
                            }
                          });
                        },
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
}

// ===================== Header =====================

class _Header extends StatelessWidget {
  final int xp;
  final int nivel;
  final int streak;
  const _Header({required this.xp, required this.nivel, required this.streak});

  @override
  Widget build(BuildContext context) {
    final tier = _tierFor(streak);
    final flameColor = _flameColorForTier(tier);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100), // 👈 responsive
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.flag_outlined,
                    color: _brandYellow,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mis Retos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  _ChipBadge(
                    icon: Icons.local_fire_department,
                    label: '$streak',
                    pillColor: Colors.white,
                    iconColor: flameColor,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Fila de insignias objetivo (3d, 10d, 30d, 100d, 200d)
              _StreakBadgesRow(current: streak),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize:
                        MainAxisSize.min, // 👈 evita ocupar todo el ancho
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _MiniStat(
                        icon: Icons.military_tech_outlined,
                        title: 'Nivel',
                        value: '$nivel',
                      ),
                      const _DividerV(),
                      _MiniStat(
                        icon: Icons.star_border_rounded,
                        title: 'XP',
                        value: '$xp',
                      ),
                      _DividerV(),
                      _MiniStat(
                        icon: Icons.local_fire_department,
                        title: 'Racha',
                        value: '$streak',
                      ),
                    ],
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

/// Skeleton del header (evita loader duplicado con la lista)
class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar({double w = 120, double h = 16}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.flag_outlined,
                    color: _brandYellow,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  bar(w: 140, h: 20),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          color: Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        bar(w: 28, h: 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(5, (_) => bar(w: 30, h: 14)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    bar(w: 80),
                    const _DividerV(),
                    bar(w: 80),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: Colors.white24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakBadgesRow extends StatelessWidget {
  final int current;
  const _StreakBadgesRow({required this.current});

  @override
  Widget build(BuildContext context) {
    final milestones = const [3, 10, 30, 100, 200];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: milestones.map((m) {
        final reached = current >= m;
        final tier = _tierFor(m);
        final color = _flameColorForTier(tier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              color: reached ? color : Colors.white.withOpacity(0.45),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              '${m}d',
              style: TextStyle(
                color: reached ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const _MiniStat({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _brandYellow, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DividerV extends StatelessWidget {
  const _DividerV();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white24,
    );
  }
}

class _ChipBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color pillColor;
  final Color? iconColor;
  const _ChipBadge({
    required this.icon,
    required this.label,
    required this.pillColor,
    this.iconColor,
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
          Icon(icon, size: 16, color: iconColor ?? Colors.black),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ===================== Lista de Retos =====================

class _RetosList extends StatelessWidget {
  final String todayKey;
  final bool working;
  final Future<void> Function(String retoId, Map<String, dynamic> reto)
  onCompletar;
  const _RetosList({
    required this.todayKey,
    required this.onCompletar,
    required this.working,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .snapshots(),
      builder: (context, meSnap) {
        if (meSnap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: LoadingIndicator(message: 'Cargando datos…'),
          );
        }
        final me = meSnap.data?.data() ?? {};
        final subrol = (me['subrol'] as String?)?.trim();

        if (subrol == null || subrol.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 40, color: _brandYellow),
                  const SizedBox(height: 12),
                  const Text(
                    'Debes seleccionar tu subrol (Bomberman o Gruaman) para ver y completar retos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Ir a Mi Perfil'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandYellow,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return _RetosQuery(
          subrol: subrol,
          todayKey: todayKey,
          onCompletar: onCompletar,
          working: working,
        );
      },
    );
  }
}

class _RetosQuery extends StatelessWidget {
  final String subrol;
  final String todayKey;
  final bool working;
  final Future<void> Function(String retoId, Map<String, dynamic> reto)
  onCompletar;

  const _RetosQuery({
    required this.subrol,
    required this.todayKey,
    required this.onCompletar,
    required this.working,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('retos')
          .where('activa', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: LoadingIndicator(message: 'Cargando retos…'),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error cargando retos:\n${snap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final all = snap.data?.docs ?? [];
        final retoDocs = all.where((d) {
          final data = (d.data() as Map<String, dynamic>? ?? {});
          final target = (data['subrol'] ?? '') as String; // docs usan 'subrol'
          return target.isEmpty || target == subrol;
        }).toList();

        if (retoDocs.isEmpty) {
          return const Center(
            child: Text('No hay retos activos para tu subrol.'),
          );
        }

        // Orden por 'orden'
        retoDocs.sort((a, b) {
          final da = (a.data() as Map<String, dynamic>)
            ..removeWhere((k, v) => v == null);
          final db = (b.data() as Map<String, dynamic>)
            ..removeWhere((k, v) => v == null);
          final oa = (da['orden'] ?? (1 << 30)) as int;
          final ob = (db['orden'] ?? (1 << 30)) as int;
          return oa.compareTo(ob);
        });

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .collection('tareasDiarias')
              .where('fechaClave', isEqualTo: todayKey)
              .snapshots(),
          builder: (context, doneSnap) {
            final doneSet = <String>{};
            for (final d in (doneSnap.data?.docs ?? [])) {
              final m = d.data() as Map<String, dynamic>;
              final rid = m['retoId'] as String?;
              if (rid != null) doneSet.add(rid);
            }

            // —— Responsive: centramos y limitamos ancho máximo del feed
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: IgnorePointer(
                  ignoring: working,
                  child: Opacity(
                    opacity: working ? 0.6 : 1,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: retoDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final data =
                            retoDocs[i].data() as Map<String, dynamic>? ?? {};
                        final id = retoDocs[i].id;
                        final titulo = (data['titulo'] ?? 'Reto') as String;
                        final desc = (data['descripcion'] ?? '') as String;
                        final xp = (data['xp'] is int) ? data['xp'] as int : 0;
                        final yaHoy = doneSet.contains(id);

                        return _RetoCard(
                          title: titulo,
                          desc: desc,
                          xp: xp,
                          completed: yaHoy,
                          onTap: yaHoy ? null : () => onCompletar(id, data),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ===================== Tarjeta de Reto (estilo Duolingo) =====================

class _RetoCard extends StatelessWidget {
  final String title;
  final String desc;
  final int xp;
  final bool completed;
  final VoidCallback? onTap;
  const _RetoCard({
    required this.title,
    required this.desc,
    required this.xp,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Chip(
      label: Text(
        '+${xp}XP',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      backgroundColor: _brandYellowSoft,
      side: const BorderSide(color: _brandYellow),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: completed ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: completed ? Colors.grey.shade300 : const Color(0xFFE8EEF8),
        ),
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
              // Icono grande
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: completed
                      ? Colors.grey.shade300
                      : _brandBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: completed
                        ? Colors.grey.shade400
                        : _brandBlue.withOpacity(0.3),
                  ),
                ),
                child: Icon(
                  completed ? Icons.check_circle : Icons.flag_outlined,
                  color: completed ? Colors.green : _brandBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        badge,
                        const Spacer(),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: completed
                              ? const _CompletedPill()
                              : ElevatedButton.icon(
                                  key: const ValueKey('btn'),
                                  onPressed: onTap,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Completar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _brandBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedPill extends StatelessWidget {
  const _CompletedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pill'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: const [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          SizedBox(width: 6),
          Text(
            'Completado',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
