import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rive/rive.dart';
import 'package:lottie/lottie.dart';

// 👇 Pantalla para reenviar/cotejar verificación
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ===== Paleta (match con Register / Verify) =====
  static const primaryBlue = Color(0xFF0E5AA7);
  static const primaryBlueDark = Color(0xFF0A4682);
  static const accentYellow = Color(0xFFFFC107);
  static const surface = Colors.white;

  // ===== Form =====
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _obscure = true;
  bool _submitting = false;

  // ===== Forgot password state =====
  static const _resetCooldownSeconds = 30;
  int _resetSecondsLeft = 0;
  Timer? _resetTimer;
  bool _resetBusy = false;

  // ===== Rive =====
  StateMachineController? _riveController;
  SMIInput<bool>? isFocus;
  SMIInput<bool>? isPrivateField;
  SMIInput<bool>? isPrivateFieldShow;
  SMITrigger? successTrigger;
  SMITrigger? failTrigger;

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) _onEmailTap();
    });
    _passFocus.addListener(() {
      if (_passFocus.hasFocus) _onPasswordTap();
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    emailController.dispose();
    passwordController.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
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
    isPrivateFieldShow?.change(false);
  }

  void _togglePasswordView() {
    setState(() => _obscure = !_obscure);
    isPrivateFieldShow?.change(!_obscure);
    isPrivateField?.change(true);
    isFocus?.change(false);
  }

  // ---- UI helpers
  void _showSnack(String msg, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return "No existe una cuenta con ese correo.";
      case 'wrong-password':
        return "Contraseña incorrecta.";
      case 'invalid-email':
        return "Correo inválido.";
      case 'user-disabled':
        return "La cuenta está deshabilitada.";
      case 'too-many-requests':
        return "Demasiados intentos. Intenta más tarde.";
      case 'network-request-failed':
        return "Sin conexión. Verifica tu internet.";
      default:
        return "No se pudo iniciar sesión. (${e.code})";
    }
  }

  InputDecoration _inputDecor({
    String? label,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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

  // ---- Login principal con verificación de correo
  Future<void> _handleLogin() async {
    if (_submitting) return;

    if (!_formKey.currentState!.validate()) {
      failTrigger?.fire();
      _showSnack("Completa los campos.");
      return;
    }

    setState(() => _submitting = true);

    // reset flags para no bloquear triggers
    isFocus?.change(false);
    isPrivateField?.change(false);
    isPrivateFieldShow?.change(false);
    await Future.delayed(const Duration(milliseconds: 60));

    final email = emailController.text.trim();
    final pass = passwordController.text.trim();

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      // Recarga y comprueba verificación
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;

      if (!verified) {
        // Ir a VerifyEmailScreen para reenviar y comprobar
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
        );

        // Relee el usuario por si se verificó mientras estaba en esa pantalla
        await FirebaseAuth.instance.currentUser?.reload();
        final nowVerified =
            FirebaseAuth.instance.currentUser?.emailVerified ?? false;

        if (result == true || nowVerified) {
          successTrigger?.fire();
          await Future.delayed(const Duration(milliseconds: 800));
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/retos');
        } else {
          await FirebaseAuth.instance.signOut();
          failTrigger?.fire();
          _showSnack("Debes verificar tu correo para continuar.");
        }
        return;
      }

      // Si ya venía verificado desde antes:
      successTrigger?.fire();
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/retos');
    } on FirebaseAuthException catch (e) {
      failTrigger?.fire();
      _showSnack(_mapAuthError(e));
    } catch (_) {
      failTrigger?.fire();
      _showSnack("Ocurrió un error inesperado.");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ------ Forgot password (bottom sheet + cooldown + backoff)
  Future<void> _handleResetPassword() async {
    if (_resetBusy || _resetSecondsLeft > 0) return;

    String email = emailController.text.trim();
    final emailOk = _isValidEmail(email);

    if (!emailOk) {
      final filled = await _askEmailSheet(initialEmail: email);
      if (filled == null) return; // canceló
      email = filled.trim();
    }

    setState(() => _resetBusy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      ); // 👈 sin acs
      _showSnack(
        "Te enviamos un correo para restablecer tu contraseña.",
        color: Colors.green,
      );
      _startResetCooldown();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        _showSnack(
          "Has solicitado varios correos en poco tiempo. Intenta nuevamente más tarde.",
          color: Colors.orange,
        );
        _startResetCooldown(overrideSeconds: 120); // backoff 2 minutos
      } else {
        _showSnack(_mapAuthError(e));
      }
    } catch (_) {
      _showSnack("No se pudo enviar el correo de recuperación.");
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  bool _isValidEmail(String x) {
    return RegExp(
      r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$",
    ).hasMatch(x.trim());
  }

  void _startResetCooldown({int? overrideSeconds}) {
    _resetTimer?.cancel();
    setState(
      () => _resetSecondsLeft = overrideSeconds ?? _resetCooldownSeconds,
    );
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resetSecondsLeft <= 1) {
        setState(() => _resetSecondsLeft = 0);
        t.cancel();
      } else {
        setState(() => _resetSecondsLeft -= 1);
      }
    });
  }

  Future<String?> _askEmailSheet({String initialEmail = ''}) async {
    final sheetForm = GlobalKey<FormState>();
    final c = TextEditingController(text: initialEmail);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Form(
            key: sheetForm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Recuperar contraseña",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: c,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecor(
                    label: "Correo",
                    hint: "tucorreo@ejemplo.com",
                  ),
                  validator: (v) =>
                      _isValidEmail(v ?? '') ? null : "Correo inválido",
                  autofocus: true,
                  onFieldSubmitted: (_) async {
                    if (sheetForm.currentState?.validate() ?? false) {
                      Navigator.pop(ctx, c.text);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text("Cancelar"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          if (sheetForm.currentState?.validate() ?? false) {
                            Navigator.pop(ctx, c.text);
                          }
                        },
                        child: const Text("Enviar enlace"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final resetLabel = _resetSecondsLeft > 0
        ? "¿Olvidaste tu contraseña? (${_resetSecondsLeft}s)"
        : "¿Olvidaste tu contraseña?";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        title: const Text("Iniciar sesión"),
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Rive arriba
                  SizedBox(
                    height: 240,
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

                  // Tarjeta formulario
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
                                    // Email
                                    TextFormField(
                                      controller: emailController,
                                      focusNode: _emailFocus,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      onTap: _onEmailTap,
                                      decoration: _inputDecor(
                                        label: "Email",
                                        hint: "tucorreo@ejemplo.com",
                                      ),
                                      validator: (v) {
                                        final x = (v ?? '').trim();
                                        if (x.isEmpty)
                                          return "Ingresa tu email";
                                        final ok = RegExp(
                                          r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$",
                                        ).hasMatch(x);
                                        return ok ? null : "Email no válido";
                                      },
                                      onFieldSubmitted: (_) => FocusScope.of(
                                        context,
                                      ).requestFocus(_passFocus),
                                    ),
                                    const SizedBox(height: 14),

                                    // Password
                                    TextFormField(
                                      controller: passwordController,
                                      focusNode: _passFocus,
                                      obscureText: _obscure,
                                      textInputAction: TextInputAction.done,
                                      onTap: _onPasswordTap,
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
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? "Ingresa tu contraseña"
                                          : null,
                                      onFieldSubmitted: (_) => _handleLogin(),
                                    ),
                                    const SizedBox(height: 10),

                                    // ¿Olvidaste tu contraseña?
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed:
                                            (_submitting ||
                                                _resetBusy ||
                                                _resetSecondsLeft > 0)
                                            ? null
                                            : _handleResetPassword,
                                        icon: const Icon(Icons.help_outline),
                                        label: Text(resetLabel),
                                        style: TextButton.styleFrom(
                                          foregroundColor: primaryBlueDark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // Botón amarillo
                                    SizedBox(
                                      height: 52,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(
                                          Icons.login_rounded,
                                          color: Colors.white,
                                        ),
                                        onPressed: _submitting
                                            ? null
                                            : _handleLogin,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accentYellow,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        label: _submitting
                                            ? SizedBox(
                                                height: 28,
                                                width: 28,
                                                child: Lottie.asset(
                                                  'lottie/loading.json',
                                                  repeat: true,
                                                ),
                                              )
                                            : const Text(
                                                "Iniciar sesión",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: Colors.white,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    // Crear cuenta
                                    Column(
                                      children: [
                                        const Text("¿No tienes cuenta?"),
                                        TextButton(
                                          onPressed: _submitting
                                              ? null
                                              : () => Navigator.pushNamed(
                                                  context,
                                                  '/register',
                                                ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: primaryBlue,
                                          ),
                                          child: const Text(
                                            "Crear una",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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

          // Overlay de carga
          if (_submitting)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black38,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: Lottie.asset(
                            'lottie/loading.json',
                            repeat: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Validando credenciales…",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
