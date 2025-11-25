import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/retos_screen.dart';
import 'screens/home_shell.dart';

/// Paleta corporativa
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);
const kCorpBlueDark = Color(0xFF0A3A7B);

/// Tonos fríos para UI
const kCardBlueBg = Color(0xFFF6FAFF); // fondo por defecto de Card
const kCardBlueBorder = Color(0xFFE3E8FF); // borde de Card y chips
const kPillBlueBg = Color(0xFFF3F6FF); // fondo de chips y entradas

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(); // SIN options (ya configurado nativo)
  } else {
    Firebase.app();
  }

  runApp(const CuartelApp());
}

class CuartelApp extends StatelessWidget {
  const CuartelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cuartel de Bombermans',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kCorpBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,

        // 🔵 Cards azules y sin tint “marrón” de M3
        cardTheme: const CardThemeData(
          color: kCardBlueBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: kCardBlueBorder),
          ),
        ),

        // 🔵 Chips y “píldoras” frías por defecto
        chipTheme: ChipThemeData(
          backgroundColor: kPillBlueBg,
          selectedColor: kCorpYellow,
          disabledColor: const Color(0xFFECEFF8),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: kCorpBlue,
          ),
          secondaryLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: kCorpBlue,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: const StadiumBorder(side: BorderSide(color: kCardBlueBorder)),
          brightness: Brightness.light,
        ),

        // 🔵 Inputs a juego (buscadores, etc.)
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: kPillBlueBg,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: kCardBlueBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: kCorpBlue),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),

        // 🔵 Diálogos sin tintes y con bordes redondeados
        dialogTheme: const DialogThemeData(
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),

        // (Opcional) Popup menus sin tint
        popupMenuTheme: const PopupMenuThemeData(
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      home: const AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/retos': (_) => const RetosScreen(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          return EnsureUserDoc(user: user, child: const HomeShell());
        }
        return const LoginScreen();
      },
    );
  }
}

class EnsureUserDoc extends StatefulWidget {
  final User user;
  final Widget child;
  const EnsureUserDoc({super.key, required this.user, required this.child});

  @override
  State<EnsureUserDoc> createState() => _EnsureUserDocState();
}

class _EnsureUserDocState extends State<EnsureUserDoc> {
  bool _ran = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ran) return;
    _ran = true;
    Future.microtask(() => ensureUserDoc(widget.user));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> ensureUserDoc(User user) async {
  final ref = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
  final snap = await ref.get();

  const schemaVersion = 1;

  // ⚠️ Campos iniciales coherentes con Leaderboard y Retos
  final base = <String, dynamic>{
    'uid': user.uid,
    'email': user.email,
    'xp': 0,
    'nivel': 1,
    'roles': ['operario'],
    'proyectoId': null,
    'subrol': null,

    // Racha general (cualquier reto completado 1 vez al día)
    'streak': 0,
    'streakLastDate': null, // String YYYYMMDD o null
    // Racha específica de grúa (solo si tipo == sin_paro_grua y marcó OK)
    'streak_grua': 0,
    'streakGruaLastDate': null, // String YYYYMMDD o null
    // Racha específica de bomba (por si la quieres usar después)
    'streak_bomba': 0,
    'streakBombaLastDate': null, // String YYYYMMDD o null

    'schemaVersion': schemaVersion,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (!snap.exists) {
    await ref.set({
      ...base,
      'fechaRegistro': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return;
  }

  final data = snap.data() ?? <String, dynamic>{};
  final patch = <String, dynamic>{};

  base.forEach((k, v) {
    if (!data.containsKey(k) || data[k] == null) {
      patch[k] = v;
    }
  });

  final currentVer = (data['schemaVersion'] ?? 0) as int;
  if (currentVer < schemaVersion) {
    patch['schemaVersion'] = schemaVersion;
  }

  if (patch.isNotEmpty) {
    patch['updatedAt'] = FieldValue.serverTimestamp();
    await ref.set(patch, SetOptions(merge: true));
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 220,
          height: 220,
          child: Lottie.asset('lottie/loading.json', repeat: true),
        ),
      ),
    );
  }
}
