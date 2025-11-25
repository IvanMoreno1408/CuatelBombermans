// lib/screens/profile_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/imgbb_service.dart';
import '../widgets/loading_indicator.dart'; // 👈 nuevo loader Lottie

// 🌟 Avatares por defecto (públicos)
const String defaultBombermanUrl = "https://i.ibb.co/PZNw1gdH/bomberman.png";
const String defaultGruamanUrl = "https://i.ibb.co/ZzXpgrGR/gruaman.png";

// Paleta corporativa
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);
const kCorpBlueDark = Color(0xFF0A3A7B); // 👈 azul oscuro para gradiente header

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _ccCtrl = TextEditingController();

  String? _subrol; // null | 'bomberman' | 'gruaman'
  bool _saving = false;

  bool _hydrated = false;
  bool _dirty = false;

  // -------- Avatar via ImgBB --------
  final _picker = ImagePicker();
  bool _uploadingAvatar = false;

  // ⚠️ Reemplaza con tu key de ImgBB
  static const String _imgbbApiKey = '487afc84fe6511e96d614ad56e258577';
  late final ImgbbService _imgbb = ImgbbService(_imgbbApiKey);

  bool _avatarBackfilledOnce = false;

  String? _defaultAvatarForSubrol(String? s) {
    if (s == 'bomberman') return defaultBombermanUrl;
    if (s == 'gruaman') return defaultGruamanUrl;
    return null;
  }

  bool _isDefaultAvatar(String? url) {
    if (url == null || url.isEmpty) return false;
    return url == defaultBombermanUrl || url == defaultGruamanUrl;
  }

  Future<void> _ensureDefaultAvatarIfNeeded({
    required String uid,
    required String? subrol,
    required String? avatarUrl,
  }) async {
    if (_avatarBackfilledOnce) return;
    final def = _defaultAvatarForSubrol(subrol);
    if (def != null && (avatarUrl == null || avatarUrl.isEmpty)) {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'avatarUrl': def,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    _avatarBackfilledOnce = true;
  }

  Future<void> _pickAndUploadAvatar(String uid) async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Cámara'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galería'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (source == null) return; // usuario canceló

      setState(() => _uploadingAvatar = true);

      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) {
        setState(() => _uploadingAvatar = false);
        return;
      }

      final url = await _imgbb.uploadFile(
        File(picked.path),
        name: 'avatar_$uid',
      );
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'avatarUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack('Avatar actualizado ✅', color: Colors.green);
    } catch (e) {
      _snack('No se pudo actualizar el avatar', color: Colors.red);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar(String uid, String? currentSubrol) async {
    try {
      final def = _defaultAvatarForSubrol(currentSubrol);
      final update = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (def == null) {
        update['avatarUrl'] = FieldValue.delete();
      } else {
        update['avatarUrl'] = def;
      }
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .set(update, SetOptions(merge: true));

      _snack(
        def == null
            ? 'Foto eliminada. Sin imagen por defecto.'
            : 'Foto eliminada. Usando avatar por defecto.',
        color: Colors.green,
      );
    } catch (_) {
      _snack('No se pudo eliminar la foto.', color: Colors.red);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _ccCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {Color color = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveProfile(String uid) async {
    if (!_formKey.currentState!.validate()) return;

    final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    final newName = _nameCtrl.text.trim();
    final newSubrol = _subrol;

    setState(() => _saving = true);
    try {
      await userRef.set({
        'nombre': newName,
        'subrol': newSubrol,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final snap = await userRef.get();
      final currentUrl = (snap.data()?['avatarUrl'] as String?);
      final def = _defaultAvatarForSubrol(newSubrol);

      if (newSubrol != null) {
        if (currentUrl == null ||
            currentUrl.isEmpty ||
            _isDefaultAvatar(currentUrl)) {
          await userRef.set({'avatarUrl': def}, SetOptions(merge: true));
        }
      } else {
        if (_isDefaultAvatar(currentUrl)) {
          await userRef.set({
            'avatarUrl': FieldValue.delete(),
          }, SetOptions(merge: true));
        }
      }

      _dirty = false;
      _snack('Perfil actualizado ✅', color: Colors.green);
    } catch (_) {
      _snack('No se pudo actualizar el perfil.', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePasswordDialog(String email) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool working = false;

    await showDialog(
      context: context,
      barrierDismissible: !working,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> doChange() async {
            if (working) return;
            if (!formKey.currentState!.validate()) return;
            setS(() => working = true);
            try {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) throw Exception('NO_USER');

              final cred = EmailAuthProvider.credential(
                email: email,
                password: currentCtrl.text.trim(),
              );
              await user.reauthenticateWithCredential(cred);
              await user.updatePassword(newCtrl.text.trim());

              if (context.mounted) Navigator.pop(ctx);
              _snack('Contraseña actualizada ✅', color: Colors.green);
            } on FirebaseAuthException catch (e) {
              String msg = 'No se pudo actualizar la contraseña';
              if (e.code == 'wrong-password') {
                msg = 'Contraseña actual incorrecta';
              }
              if (e.code == 'weak-password') {
                msg = 'La nueva contraseña es muy débil';
              }
              _snack(msg, color: Colors.red);
            } catch (_) {
              _snack('No se pudo actualizar la contraseña', color: Colors.red);
            } finally {
              setS(() => working = false);
            }
          }

          return AlertDialog(
            title: const Text('Cambiar contraseña'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña actual',
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nueva contraseña',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Requerido';
                      if (v.length < 6) return 'Mínimo 6 caracteres';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: working ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: working ? null : doChange,
                child: working
                    ? const LoadingIndicator.button(
                        asset: 'flutter/loading.json',
                      )
                    : const Text('Actualizar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendResetEmail(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack(
        'Enviamos un correo para restablecer tu contraseña.',
        color: Colors.green,
      );
    } catch (_) {
      _snack(
        'No se pudo enviar el correo de restablecimiento.',
        color: Colors.red,
      );
    }
  }

  void _hydrateFromDoc(Map<String, dynamic> data, User user) {
    if (_hydrated && _dirty) return;

    final nombre = (data['nombre'] ?? '') as String;
    final email = (data['email'] ?? user.email ?? '-') as String;
    final cc = (data['cc'] ?? '') as String;
    final subrol = data['subrol'] as String?;

    _nameCtrl.text = nombre;
    _emailCtrl.text = email;
    _ccCtrl.text = cc;
    _subrol = subrol;

    _hydrated = true;
  }

  // —— UI label (sin tocar Firebase): operario/admin/lider → Operario/Admin/Líder
  String _roleLabel(String raw) {
    switch (raw) {
      case 'admin':
        return 'Admin';
      case 'lider':
        return 'Líder';
      case 'operario':
      default:
        return 'Operario';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('No hay usuario autenticado')),
      );
    }

    final uid = user.uid;
    final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);

    return Scaffold(
      body: Container(
        // ===== Fondo con gradiente (como en Retos/Ranking/Admin) =====
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kCorpBlue, kCorpBlueDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // ======= HEADER estilo “Mis Retos” =======
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          color: kCorpYellow,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Mi Perfil',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800, // 👈 negrita
                              ),
                        ),
                        const Spacer(),
                        // Chip con el subrol (o Sin subrol)
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: userRef.snapshots(),
                          builder: (_, s) {
                            final sub = (s.data?.data()?['subrol'] as String?);
                            final label = sub == null
                                ? 'Sin subrol'
                                : (sub == 'bomberman'
                                      ? 'Bomberman'
                                      : 'Gruaman');
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

                  // ======= CONTENIDO =======
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: userRef.snapshots(),
                        builder: (_, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            // Loader inline (no fullscreen) para evitar duplicados con HomeShell
                            return const Center(
                              child: LoadingIndicator(
                                asset: 'lottie/loading.json',
                                message: 'Cargando perfil…',
                              ),
                            );
                          }
                          if (!snap.hasData || !snap.data!.exists) {
                            return const Center(
                              child: Text('No se encontró el perfil.'),
                            );
                          }
                          final data = (snap.data!.data() ?? {})
                            ..removeWhere((k, v) => v == null);

                          _hydrateFromDoc(data, user);

                          final roles =
                              (data['roles'] as List?)?.cast<String>() ??
                              const [];
                          final rolPrincipalRaw = roles.isEmpty
                              ? 'operario'
                              : roles.first;
                          final rolPrincipalLabel = _roleLabel(rolPrincipalRaw);

                          final proyectoId = (data['proyectoId'] as String?);
                          final xp = (data['xp'] ?? 0) as int;
                          final nivel = (data['nivel'] ?? 1) as int;
                          final fechaReg = (data['fechaRegistro'] as Timestamp?)
                              ?.toDate();
                          final email = _emailCtrl.text;
                          final avatarUrl = data['avatarUrl'] as String?;

                          final streak = (data['streak'] ?? 0) as int;
                          final streakB = (data['streak_bomba'] ?? 0) as int;
                          final streakG = (data['streak_grua'] ?? 0) as int;

                          _ensureDefaultAvatarIfNeeded(
                            uid: uid,
                            subrol: _subrol,
                            avatarUrl: avatarUrl,
                          );

                          Color ringColor = Colors.white;
                          if (_subrol == 'bomberman')
                            ringColor = Colors.red.shade200;
                          if (_subrol == 'gruaman')
                            ringColor = Colors.blue.shade200;

                          const xpMax = 1000;
                          final xpProgreso = xp % xpMax;

                          // —— Responsive layout: 1 columna en móviles, 2 columnas en pantallas anchas
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 900;

                              // Secciones reutilizables
                              Widget headerCard() => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment(-1, -1),
                                    end: Alignment(1, .2),
                                    colors: [kCorpBlue, Color(0xFF3D8BFF)],
                                  ),
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  18,
                                  16,
                                  24,
                                ),
                                child: Column(
                                  children: [
                                    Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: ringColor,
                                            shape: BoxShape.circle,
                                          ),
                                          child: CircleAvatar(
                                            radius: 48,
                                            backgroundColor: Colors.white,
                                            backgroundImage:
                                                (avatarUrl != null &&
                                                    avatarUrl.isNotEmpty)
                                                ? NetworkImage(avatarUrl)
                                                : (_subrol == 'bomberman'
                                                      ? const NetworkImage(
                                                          defaultBombermanUrl,
                                                        )
                                                      : _subrol == 'gruaman'
                                                      ? const NetworkImage(
                                                          defaultGruamanUrl,
                                                        )
                                                      : null),
                                            child:
                                                (avatarUrl == null ||
                                                        avatarUrl.isEmpty) &&
                                                    _subrol == null
                                                ? Text(
                                                    ((_nameCtrl.text.isNotEmpty
                                                            ? _nameCtrl.text[0]
                                                            : email[0]))
                                                        .toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 36,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: kCorpBlue,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: _saving || _uploadingAvatar
                                              ? null
                                              : () => _pickAndUploadAvatar(uid),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: kCorpYellow,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(.15),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              _uploadingAvatar
                                                  ? Icons.hourglass_top
                                                  : Icons.edit,
                                              color: Colors.black,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: _uploadingAvatar
                                          ? null
                                          : () => _removeAvatar(uid, _subrol),
                                      borderRadius: BorderRadius.circular(999),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(.18),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: Colors.white24,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Quitar foto',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 12),
                                    Text(
                                      _nameCtrl.text.isEmpty
                                          ? 'Sin nombre'
                                          : _nameCtrl.text,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      email,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        _pill('Rol: $rolPrincipalLabel'),
                                        if (_subrol != null)
                                          _pill(
                                            'Subrol: ${_subrol! == 'bomberman' ? 'Bomberman' : 'Gruaman'}',
                                          ),
                                        _projectPillByName(proyectoId),
                                      ],
                                    ),
                                  ],
                                ),
                              );

                              Widget stats() => Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  6,
                                ),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _statChip(
                                      title: 'Nivel',
                                      value: '$nivel',
                                      icon: Icons.military_tech_outlined,
                                    ),
                                    _statChip(
                                      title: 'XP',
                                      value: '$xp',
                                      icon: Icons.flash_on_outlined,
                                      color: kCorpYellow,
                                    ),
                                    _statChip(
                                      title: 'Racha',
                                      value: '$streak',
                                      icon:
                                          Icons.local_fire_department_outlined,
                                      color: Colors.orange.shade300,
                                    ),
                                    if (streakB > 0)
                                      _statChip(
                                        title: 'Bomba',
                                        value: '$streakB',
                                        icon: Icons.water_drop_outlined,
                                        color: Colors.lightBlue.shade200,
                                      ),
                                    if (streakG > 0)
                                      _statChip(
                                        title: 'Grúa',
                                        value: '$streakG',
                                        icon: Icons.construction_outlined,
                                        color: Colors.indigo.shade200,
                                      ),
                                  ],
                                ),
                              );

                              Widget levelProgress() => Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Progreso de nivel',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: LinearProgressIndicator(
                                        value: xpMax == 0
                                            ? 0
                                            : (xpProgreso / xpMax),
                                        minHeight: 12,
                                        backgroundColor: Colors.grey.shade300,
                                        color: kCorpBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Center(
                                      child: Text(
                                        'Nivel $nivel • $xpProgreso / $xpMax XP',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              Widget formCard() => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: isWide
                                          ? 560
                                          : 720, // 👈 más ajustado en wide
                                    ),
                                    child: Form(
                                      key: _formKey,
                                      onChanged: () => _dirty = true,
                                      child: Column(
                                        children: [
                                          TextFormField(
                                            controller: _nameCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Nombre completo',
                                              border: OutlineInputBorder(),
                                            ),
                                            validator: (v) =>
                                                (v == null || v.trim().isEmpty)
                                                ? 'Ingresa tu nombre'
                                                : null,
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _emailCtrl,
                                            enabled: false,
                                            decoration: const InputDecoration(
                                              labelText: 'Correo',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _ccCtrl,
                                            enabled: false,
                                            decoration: const InputDecoration(
                                              labelText: 'Cédula / CC',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),

                                          DropdownButtonFormField<String?>(
                                            value:
                                                (_subrol == 'bomberman' ||
                                                    _subrol == 'gruaman')
                                                ? _subrol
                                                : null,
                                            items: const [
                                              DropdownMenuItem<String?>(
                                                value: null,
                                                child: Text('Sin subrol'),
                                              ),
                                              DropdownMenuItem<String?>(
                                                value: 'bomberman',
                                                child: Text('Bomberman'),
                                              ),
                                              DropdownMenuItem<String?>(
                                                value: 'gruaman',
                                                child: Text('Gruaman'),
                                              ),
                                            ],
                                            onChanged: (v) => setState(() {
                                              _subrol = v;
                                              _dirty = true;
                                            }),
                                            decoration: const InputDecoration(
                                              labelText: 'Subrol',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),

                                          ListTile(
                                            leading: const Icon(
                                              Icons.verified_user_outlined,
                                            ),
                                            title: const Text('Rol principal'),
                                            subtitle: Text(rolPrincipalLabel),
                                          ),
                                          if (proyectoId != null)
                                            ListTile(
                                              leading: const Icon(
                                                Icons.apartment_outlined,
                                              ),
                                              title: const Text(
                                                'Proyecto (ID)',
                                              ),
                                              subtitle: Text(proyectoId),
                                            ),
                                          if (fechaReg != null)
                                            ListTile(
                                              leading: const Icon(
                                                Icons.calendar_today_outlined,
                                              ),
                                              title: const Text(
                                                'Fecha de registro',
                                              ),
                                              subtitle: Text(
                                                '${fechaReg.day.toString().padLeft(2, '0')}/${fechaReg.month.toString().padLeft(2, '0')}/${fechaReg.year}',
                                              ),
                                            ),

                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: _saving
                                                      ? null
                                                      : () => _sendResetEmail(
                                                          email,
                                                        ),
                                                  icon: const Icon(
                                                    Icons.alternate_email,
                                                  ),
                                                  label: const Text(
                                                    'Restablecer por correo',
                                                  ),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                        foregroundColor:
                                                            kCorpBlue,
                                                        side: const BorderSide(
                                                          color: kCorpBlue,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  onPressed: _saving
                                                      ? null
                                                      : () =>
                                                            _changePasswordDialog(
                                                              email,
                                                            ),
                                                  icon: const Icon(
                                                    Icons.lock_reset,
                                                  ),
                                                  label: const Text(
                                                    'Cambiar contraseña',
                                                  ),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            kCorpBlue,
                                                        foregroundColor:
                                                            Colors.white,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: _saving
                                                  ? null
                                                  : () => _saveProfile(uid),
                                              icon: const Icon(Icons.save),
                                              label: const Text(
                                                'Guardar cambios',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kCorpYellow,
                                                foregroundColor: Colors.black,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () async =>
                                                  FirebaseAuth.instance
                                                      .signOut(),
                                              icon: const Icon(Icons.logout),
                                              label: const Text(
                                                'Cerrar sesión',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.grey.shade800,
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );

                              if (!isWide) {
                                // —— Móvil: una sola columna (como antes)
                                return ListView(
                                  children: [
                                    headerCard(),
                                    stats(),
                                    levelProgress(),
                                    const Divider(height: 24),
                                    formCard(),
                                  ],
                                );
                              }

                              // —— Pantallas anchas: header/estadísticas a la izquierda, formulario a la derecha
                              return ListView(
                                padding: const EdgeInsets.only(bottom: 24),
                                children: [
                                  // el header conserva el borde redondeado superior
                                  headerCard(),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      12,
                                      12,
                                      0,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Columna izquierda (stats + progreso)
                                        Expanded(
                                          flex: 6,
                                          child: Column(
                                            children: [
                                              stats(),
                                              levelProgress(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Columna derecha (formulario)
                                        Expanded(flex: 7, child: formCard()),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),

              if (_saving)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black26,
                      child: const Center(
                        child: const Center(
                          child: LoadingIndicator(
                            asset: 'lottie/loading.json',
                            message: 'Guardando cambios…',
                          ),
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

  /// Pill con el **nombre del proyecto** usando `proyectos/{id}.nombre`.
  Widget _projectPillByName(String? projectId) {
    if (projectId == null || projectId.isEmpty) {
      return _pill('Proyecto: Sin asignar');
    }
    final stream = FirebaseFirestore.instance
        .collection('proyectos')
        .doc(projectId)
        .snapshots();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (_, snap) {
        String name = '...';
        if (snap.hasData && snap.data!.exists) {
          final m = snap.data!.data() ?? {};
          final n = (m['nombre'] ?? '') as String;
          if (n.isNotEmpty) name = n;
        }
        return _pill('Proyecto: $name');
      },
    );
  }
}

/// ======= UI helpers =======

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
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );
}

Widget _statChip({
  required String title,
  required String value,
  required IconData icon,
  Color? color,
}) {
  return Container(
    width: 150,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: (color ?? Colors.white),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black12),
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
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
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
