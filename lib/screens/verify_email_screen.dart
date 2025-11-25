import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rive/rive.dart';
import 'package:lottie/lottie.dart';

import '../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  // ======= Paleta (match con Login / Register) =======
  static const primaryBlue = Color(0xFF0E5AA7);
  static const primaryBlueDark = Color(0xFF0A4682);
  static const accentYellow = Color(0xFFFFC107);
  static const surface = Colors.white;

  final _auth = FirebaseAuth.instance;
  final _authService = AuthService();

  bool _busy = false;
  String? _message;

  // Cooldown para Reenviar
  static const _cooldownSeconds = 30;
  int _secondsLeft = 0;
  Timer? _cooldownTimer;

  // Rive (mismo asset/inputs para look & feel consistente)
  StateMachineController? _riveController;
  SMIInput<bool>? isFocus;
  SMIInput<bool>? isPrivateField;
  SMIInput<bool>? isPrivateFieldShow;
  SMITrigger? successTrigger;
  SMITrigger? failTrigger;

  @override
  void initState() {
    super.initState();
    // ⛔️ No enviamos automáticamente; el primer envío ya se hizo en RegisterScreen.
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ======= UI helpers =======
  void _showSnack(String msg, {Color color = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ======= Lógica =======
  Future<void> _sendVerificationEmail({bool auto = false}) async {
    if (_busy || _secondsLeft > 0) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showSnack(
          "No hay sesión activa. Vuelve a iniciar sesión.",
          color: Colors.red,
        );
        if (mounted) Navigator.pop(context, false);
        return;
      }

      // Opción A: SIN Dynamic Links → plantilla por defecto de Firebase
      await _authService.sendEmailVerification();

      successTrigger?.fire();
      setState(() {
        _message = auto
            ? "Te enviamos un correo de verificación. Revisa tu bandeja o spam."
            : "Te envié un nuevo correo de verificación.";
      });

      _startCooldown();
    } on FirebaseAuthException catch (e) {
      failTrigger?.fire();
      if (e.code == 'too-many-requests') {
        setState(() {
          _message =
              "Has solicitado varios correos en poco tiempo. Espera un momento e inténtalo de nuevo.";
        });
        _startCooldown(overrideSeconds: 120); // backoff más largo (2 min)
      } else {
        setState(() {
          _message =
              "No pude enviar el correo de verificación: ${e.message ?? e.code}";
        });
      }
    } catch (e) {
      failTrigger?.fire();
      setState(() {
        _message = "No pude enviar el correo de verificación: $e";
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown({int? overrideSeconds}) {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = overrideSeconds ?? _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        setState(() => _secondsLeft = 0);
        timer.cancel();
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _checkVerified() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await _auth.currentUser?.reload();
      final ok = _auth.currentUser?.emailVerified ?? false;
      if (ok) {
        successTrigger?.fire();
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        Navigator.pop(context, true); // <- volver al caller como verificado
      } else {
        failTrigger?.fire();
        setState(() {
          _message =
              "Aún no está verificado. Revisa tu email o inténtalo en unos segundos.";
        });
      }
    } catch (e) {
      failTrigger?.fire();
      setState(() {
        _message = "No pude comprobar la verificación: $e";
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentUser?.email ?? '';
    final size = MediaQuery.of(context).size;
    final textScale = MediaQuery.of(context).textScaleFactor;

    // Medidas responsivas comunes
    final double teddyHeight = (size.height * 0.28).clamp(
      180.0,
      size.height * 0.35,
    );
    final double horizontalPad = size.width < 380 ? 12 : 16;
    final double cardMaxWidth = size.width >= 720 ? 560 : 520;

    // Loader del botón (se adapta a la escala de texto y ancho disponible)
    final double inlineLoaderSide = (24.0 * textScale).clamp(
      22.0,
      28.0,
    ); // 22–28 px

    // Loader del overlay
    final double overlayLoaderSide = (size.width * 0.35).clamp(
      180.0,
      280.0,
    ); // 180–280 px

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Verifica tu correo"),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Center(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    // ======= Rive sin fondo, sobre la tarjeta =======
                    SizedBox(
                      height: teddyHeight,
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

                          // Neutral
                          isFocus?.change(false);
                          isPrivateField?.change(false);
                          isPrivateFieldShow?.change(false);
                        },
                      ),
                    ),

                    // ======= Tarjeta principal (responsive) =======
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: cardMaxWidth),
                        child: Container(
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE6E8EC)),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.mark_email_unread_outlined,
                                      color: primaryBlue,
                                    ),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        "Confirma tu email",
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: primaryBlue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                Text(
                                  email.isEmpty
                                      ? "Te enviamos un enlace de verificación a tu correo."
                                      : "Te enviamos un enlace de verificación a:\n$email",
                                  textAlign: TextAlign.left,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 12),

                                if (_message != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7F9FC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE6E8EC),
                                      ),
                                    ),
                                    child: Text(
                                      _message!,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),

                                // Botón Amarillo: Ya verifiqué
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    onPressed: _busy ? null : _checkVerified,
                                    icon: const Icon(
                                      Icons.verified,
                                      color: Colors.white,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentYellow,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    label: _busy
                                        ? SizedBox(
                                            height: inlineLoaderSide,
                                            width: inlineLoaderSide,
                                            child: Lottie.asset(
                                              'lottie/loading.json',
                                              repeat: true,
                                            ),
                                          )
                                        : const Text(
                                            "Ya verifiqué, continuar",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Botón Reenviar (azul contorneado) con cooldown
                                SizedBox(
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: (_busy || _secondsLeft > 0)
                                        ? null
                                        : () => _sendVerificationEmail(),
                                    icon: const Icon(Icons.refresh),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: primaryBlueDark,
                                      side: const BorderSide(
                                        color: primaryBlue,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    label: Text(
                                      _secondsLeft > 0
                                          ? "Reenviar (${_secondsLeft}s)"
                                          : "Reenviar correo",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // Volver
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.pop(context, false),
                                  icon: const Icon(Icons.arrow_back),
                                  style: TextButton.styleFrom(
                                    foregroundColor: primaryBlueDark,
                                  ),
                                  label: const Text("Volver"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ======= Overlay de carga global (responsivo) =======
          if (_busy)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black26,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: overlayLoaderSide,
                          height: overlayLoaderSide,
                          child: Lottie.asset(
                            'lottie/loading.json',
                            repeat: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Procesando…",
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
