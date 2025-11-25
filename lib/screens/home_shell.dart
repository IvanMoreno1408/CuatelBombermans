// lib/screens/home_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // para haptics (opcional)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'retos_screen.dart';
import 'profile_screen.dart';
import 'admin_retos_list_screen.dart';
import 'admin_projects_screen.dart';
import 'form_templates_list_screen.dart';
import 'leaderboard_screen.dart';
import '../widgets/loading_indicator.dart'; // 👈 importa el nuevo loader

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Máximo de tabs esperados (3 base + 1 admin/líder + perfil = 5)
  // dejamos 6 por si crece en el futuro.
  final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    6,
    (_) => GlobalKey<NavigatorState>(),
  );

  Future<bool> _onWillPop() async {
    final nav = _navKeys[_index].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Si aún no hay UID (Auth inicializando), mostramos un único loader de pantalla completa.
    if (uid == null) {
      return const Scaffold(
        body: LoadingIndicator(
          fullscreen: true,
          asset: 'lottie/loading.json',
          message: 'Cargando…',
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // Mientras obtenemos el perfil, un solo loader global.
          return const Scaffold(
            body: LoadingIndicator(
              fullscreen: true,
              asset: 'lottie/loading.json',
              message: 'Obteniendo tu perfil…',
            ),
          );
        }

        final data = snap.data?.data() ?? {};
        final roles = (data['roles'] as List?)?.cast<String>() ?? const [];
        final isAdmin = roles.contains('admin');
        final isLeader = roles.contains('lider');
        final leaderProjectId = (data['proyectoId'] as String?);

        // Helper local para crear items con animación y variantes de ícono
        BottomNavigationBarItem _navItem({
          required int idx,
          required IconData iconOutlined,
          required IconData iconFilled,
          required String label,
        }) {
          Widget buildIcon(IconData icon, bool selected) {
            return TweenAnimationBuilder<double>(
              key: ValueKey('${label}_${selected ? "on" : "off"}'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              tween: Tween(
                begin: selected ? 0.90 : 1.00,
                end: selected ? 1.00 : 0.96,
              ),
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: selected ? 1.0 : 0.72,
                    child: Icon(icon),
                  ),
                );
              },
            );
          }

          return BottomNavigationBarItem(
            icon: buildIcon(iconOutlined, false),
            activeIcon: buildIcon(iconFilled, true),
            label: label,
          );
        }

        // ===== Tabs base
        final tabs = <Widget>[
          const RetosScreen(),
          const FormTemplatesListScreen(),
          const LeaderboardScreen(),
        ];

        // Ítems base con mejores íconos (outlined/filled)
        final items = <BottomNavigationBarItem>[
          _navItem(
            idx: 0,
            iconOutlined: Icons.flag_outlined,
            iconFilled: Icons.flag,
            label: 'Retos',
          ),
          _navItem(
            idx: 1,
            iconOutlined: Icons.description_outlined,
            iconFilled: Icons.description,
            label: 'Formularios',
          ),
          _navItem(
            idx: 2,
            iconOutlined: Icons.emoji_events_outlined,
            iconFilled: Icons.emoji_events,
            label: 'Ranking',
          ),
        ];

        // ===== ADMIN o LÍDER
        if (isAdmin) {
          tabs.add(const AdminRetosListScreen());
          items.add(
            _navItem(
              idx: items.length,
              iconOutlined: Icons.admin_panel_settings_outlined,
              iconFilled: Icons.admin_panel_settings,
              label: 'Admin',
            ),
          );
        } else if (isLeader) {
          tabs.add(
            AdminProjectsScreen(
              isAdmin: false,
              leaderProjectId: leaderProjectId,
            ),
          );
          items.add(
            _navItem(
              idx: items.length,
              iconOutlined: Icons.groups_2_outlined,
              iconFilled: Icons.groups_2,
              label: 'Equipo',
            ),
          );
        }

        // ===== PERFIL SIEMPRE al final
        tabs.add(const ProfileScreen());
        items.add(
          _navItem(
            idx: items.length,
            iconOutlined: Icons.person_outline,
            iconFilled: Icons.person,
            label: 'Perfil',
          ),
        );

        if (_index >= tabs.length) _index = tabs.length - 1;

        return WillPopScope(
          onWillPop: _onWillPop,
          child: Scaffold(
            body: IndexedStack(
              index: _index,
              children: List.generate(tabs.length, (i) {
                final key = _navKeys[i];
                return Navigator(
                  key: key,
                  onGenerateRoute: (settings) {
                    return MaterialPageRoute(
                      builder: (_) => tabs[i],
                      settings: settings,
                    );
                  },
                );
              }),
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _index,
              onTap: (i) {
                if (i != _index) {
                  HapticFeedback.lightImpact(); // toquecito opcional
                }
                setState(() => _index = i);
              },
              items: items,
              type: BottomNavigationBarType.fixed,
              // Paleta y tamaños coherentes con el tema
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(
                context,
              ).colorScheme.onSurface.withOpacity(0.72),
              selectedIconTheme: const IconThemeData(size: 28),
              unselectedIconTheme: const IconThemeData(size: 26),
              showUnselectedLabels:
                  false, // más limpio (actívalo si lo prefieres)
            ),
          ),
        );
      },
    );
  }
}
