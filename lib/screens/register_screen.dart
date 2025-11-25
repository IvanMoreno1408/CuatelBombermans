import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rive/rive.dart';
import 'package:lottie/lottie.dart';

import '../services/auth_service.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ======= Colores =======
  static const primaryBlue = Color(0xFF0E5AA7);
  static const primaryBlueDark = Color(0xFF0A4682);
  static const accentYellow = Color(0xFFFFC107);
  static const surface = Colors.white;

  // ======= Form =======
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final ccController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _obscure = true;
  bool _obscureConfirm = true; // 👈 nuevo para confirmar contraseña
  bool _submitting = false;

  // ======= Rive =======
  SMIInput<bool>? isFocus;
  SMIInput<bool>? isPrivateField;
  SMIInput<bool>? isPrivateFieldShow;
  SMITrigger? successTrigger;
  SMITrigger? failTrigger;
  StateMachineController? _riveController;

  @override
  void initState() {
    super.initState();
    passwordController.addListener(() => setState(() {}));
  }

  // ---- Rive helpers
  void _onEmailTap() {
    isFocus?.change(true);
    isPrivateField?.change(false);
    isPrivateFieldShow?.change(false);
  }

  void _onPasswordTap() {
    isFocus?.change(false);
    isPrivateField?.change(true);
    isPrivateFieldShow?.change(!_obscure); // mira/oculta según estado
  }

  void _togglePasswordView() {
    setState(() => _obscure = !_obscure);
    isPrivateFieldShow?.change(!_obscure);
    isPrivateField?.change(true);
    isFocus?.change(false);
  }

  // 👇 NUEVO: confirmación
  void _onConfirmTap() {
    isFocus?.change(false);
    isPrivateField?.change(true);
    isPrivateFieldShow?.change(!_obscureConfirm);
  }

  void _toggleConfirmView() {
    setState(() => _obscureConfirm = !_obscureConfirm);
    isPrivateFieldShow?.change(!_obscureConfirm);
    isPrivateField?.change(true);
    isFocus?.change(false);
  }

  // ---- Fortaleza simple de contraseña
  (double, String) _passwordStrength(String v) {
    int score = 0;
    if (v.length >= 6) score++;
    if (v.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(v)) score++;
    if (RegExp(r'[0-9]').hasMatch(v)) score++;
    if (RegExp(r'[!@#\$%\^&\*\(\)_\+\-=\[\]{};:"\\|,.<>\/?~`]').hasMatch(v))
      score++;
    final pct = (score / 5).clamp(0, 1).toDouble();
    final label = switch (score) {
      0 || 1 => 'Muy débil',
      2 => 'Débil',
      3 => 'Media',
      4 => 'Fuerte',
      _ => 'Muy fuerte',
    };
    return (pct, label);
  }

  // ---- Registro con transacción y verificación (sin subrol)
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      failTrigger?.fire();
      return;
    }

    setState(() => _submitting = true);

    try {
      final nombre = nameController.text.trim();
      final cc = ccController.text.trim();
      final email = emailController.text.trim();
      final pass = passwordController.text.trim();

      // 1) Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final uid = cred.user!.uid;

      // 2) Firestore (transacción)
      final fs = FirebaseFirestore.instance;
      final ccIndexRef = fs.collection('cc_index').doc(cc);
      final userRef = fs.collection('usuarios').doc(uid);

      await fs.runTransaction((tx) async {
        final ccSnap = await tx.get(ccIndexRef);
        if (ccSnap.exists) {
          throw Exception('CC_DUPLICADA');
        }

        tx.set(ccIndexRef, {
          'uid': uid,
          'cc': cc,
          'createdAt': FieldValue.serverTimestamp(),
        });

        tx.set(userRef, {
          'uid': uid,
          'nombre': nombre,
          'cc': cc,
          'email': email,
          'fechaRegistro': FieldValue.serverTimestamp(),
          'nivel': 1,
          'xp': 0,
          'roles': ['operario'],
          'proyectoId': null,
          'subrol': null, // 👈 sin dropdown, explícitamente null
          'schemaVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
          'emailVerified': false,
        });
      });

      // 3) Enviar correo de verificación
      final authService = AuthService();
      try {
        await authService.sendEmailVerification();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'too-many-requests') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Has solicitado varios correos en poco tiempo. Intenta de nuevo más tarde.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No pude enviar el correo de verificación: ${e.message ?? e.code}',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No pude enviar el correo de verificación: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // 4) UI éxito + ir a pantalla de verificación
      successTrigger?.fire();
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      final verified =
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
          ) ??
          false;

      if (verified) {
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).update(
          {'emailVerified': true, 'updatedAt': FieldValue.serverTimestamp()},
        );
        if (mounted) Navigator.pop(context);
      } else {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debes verificar tu correo para continuar.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // rollback auth si algo falla en Firestore
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        try {
          await u.delete();
        } catch (_) {}
      }

      failTrigger?.fire();
      String msg = "Error al crear la cuenta.";
      if (e is FirebaseAuthException) {
        msg = e.message ?? msg;
      } else if (e.toString().contains('CC_DUPLICADA')) {
        msg = "La cédula ingresada ya está registrada.";
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    ccController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecor({
    String? label,
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE6E8EC)),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(width: 2, color: primaryBlue),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(width: 1.2, color: Colors.redAccent),
        borderRadius: BorderRadius.circular(12),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Crear cuenta"),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  // Rive
                  SizedBox(
                    height:
                        size.height * 0.28, // responsivo (alto ~28% pantalla)
                    child: RiveAnimation.asset(
                      "images/auth_teddy.riv",
                      stateMachines: const ["Login Machine"],
                      onInit: (artboard) {
                        _riveController = StateMachineController.fromArtboard(
                          artboard,
                          "Login Machine",
                        );
                        if (_riveController == null) return;
                        artboard.addController(_riveController!);
                        isFocus = _riveController?.findInput<bool>("isFocus");
                        isPrivateField = _riveController?.findInput<bool>(
                          "isPrivateField",
                        );
                        isPrivateFieldShow = _riveController?.findInput<bool>(
                          "isPrivateFieldShow",
                        );
                        successTrigger = _riveController?.findSMI<SMITrigger>(
                          "successTrigger",
                        );
                        failTrigger = _riveController?.findSMI<SMITrigger>(
                          "failTrigger",
                        );
                      },
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: IgnorePointer(
                      ignoring: _submitting,
                      child: Opacity(
                        opacity: _submitting ? 0.6 : 1,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Container(
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE6E8EC),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 20,
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // ---------- Datos personales
                                    Row(
                                      children: const [
                                        Icon(
                                          Icons.info_outline,
                                          color: primaryBlue,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "Datos personales",
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: primaryBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    TextFormField(
                                      controller: nameController,
                                      textInputAction: TextInputAction.next,
                                      decoration: _inputDecor(
                                        label: "Nombre completo",
                                        helper: "Como aparece en tu documento",
                                      ),
                                      validator: (v) {
                                        final x = (v ?? '').trim();
                                        if (x.isEmpty)
                                          return "Ingresa tu nombre";
                                        if (x
                                                .split(' ')
                                                .where((e) => e.isNotEmpty)
                                                .length <
                                            2) {
                                          return "Escribe al menos nombre y apellido";
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    TextFormField(
                                      controller: ccController,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(10),
                                      ],
                                      textInputAction: TextInputAction.next,
                                      decoration: _inputDecor(
                                        label: "Cédula / CC",
                                        helper: "Entre 8 y 10 dígitos",
                                      ),
                                      validator: (v) {
                                        final x = (v ?? '').trim();
                                        if (x.isEmpty)
                                          return "Ingresa tu cédula";
                                        if (x.length < 8 || x.length > 10) {
                                          return "La cédula debe tener entre 8 y 10 números";
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),

                                    // ---------- Cuenta
                                    Row(
                                      children: const [
                                        Icon(
                                          Icons.lock_outline,
                                          color: primaryBlue,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "Cuenta",
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: primaryBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    TextFormField(
                                      controller: emailController,
                                      onTap: _onEmailTap,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      decoration: _inputDecor(label: "Email"),
                                      validator: (v) {
                                        final x = (v ?? '').trim();
                                        if (x.isEmpty)
                                          return "Ingresa un email";
                                        final ok = RegExp(
                                          r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$",
                                        ).hasMatch(x);
                                        return ok ? null : "Email no válido";
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    TextFormField(
                                      controller: passwordController,
                                      obscureText: _obscure,
                                      onTap: _onPasswordTap,
                                      textInputAction: TextInputAction.next,
                                      decoration: _inputDecor(
                                        label: "Contraseña",
                                        suffixIcon: IconButton(
                                          onPressed: _togglePasswordView,
                                          icon: Icon(
                                            _obscure
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: primaryBlue,
                                          ),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty)
                                          return "Ingresa una contraseña";
                                        if (v.length < 6)
                                          return "Mínimo 6 caracteres";
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 8),

                                    Builder(
                                      builder: (_) {
                                        final (p, l) = _passwordStrength(
                                          passwordController.text,
                                        );
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: LinearProgressIndicator(
                                                value: p,
                                                minHeight: 6,
                                                backgroundColor: const Color(
                                                  0xFFE6E8EC,
                                                ),
                                                color: (p >= .6)
                                                    ? primaryBlue
                                                    : accentYellow,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Fortaleza: $l",
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    // 👇 Campo Confirmar contraseña con ojo + onTap para Rive
                                    TextFormField(
                                      controller: confirmPasswordController,
                                      obscureText: _obscureConfirm,
                                      onTap: _onConfirmTap,
                                      decoration: _inputDecor(
                                        label: "Confirmar contraseña",
                                        suffixIcon: IconButton(
                                          onPressed: _toggleConfirmView,
                                          icon: Icon(
                                            _obscureConfirm
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: primaryBlue,
                                          ),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return "Confirma tu contraseña";
                                        }
                                        if (v != passwordController.text) {
                                          return "Las contraseñas no coinciden";
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 24),

                                    // ---------- Botón amarillo
                                    SizedBox(
                                      height: 52,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                        ),
                                        onPressed: _submitting
                                            ? null
                                            : _handleRegister,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accentYellow,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        label: const Text(
                                          "Crear cuenta",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    TextButton.icon(
                                      onPressed: _submitting
                                          ? null
                                          : () => Navigator.pop(context),
                                      icon: const Icon(Icons.arrow_back),
                                      label: const Text(
                                        "Ya tengo cuenta, volver al login",
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: primaryBlueDark,
                                      ),
                                    ),

                                    const SizedBox(height: 6),
                                  ],
                                ),
                              ),
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

          if (_submitting) const PositionedFillLoading(submitting: true),
        ],
      ),
    );
  }
}

// ======= Overlay de cargando (responsivo) =======
class PositionedFillLoading extends StatelessWidget {
  final bool submitting;
  const PositionedFillLoading({super.key, required this.submitting});

  @override
  Widget build(BuildContext context) {
    if (!submitting) return const SizedBox.shrink();

    // Tamaño responsivo: 35% del ancho, con límites mínimos/máximos
    final size = MediaQuery.of(context).size;
    final loaderSide = (size.width * 0.35).clamp(180.0, 280.0);

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black26,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: loaderSide,
                  height: loaderSide,
                  child: Lottie.asset('lottie/loading.json', repeat: true),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Creando usuario…",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
