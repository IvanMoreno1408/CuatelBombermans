// lib/screens/leaderboard_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/loading_indicator.dart'; // 👈 loader unificado

const String defaultBombermanUrl = "https://i.ibb.co/PZNw1gdH/bomberman.png";
const String defaultGruamanUrl = "https://i.ibb.co/ZzXpgrGR/gruaman.png";

// Paleta corporativa
const kCorpBlue = Color(0xFF005BBB);
const kCorpYellow = Color(0xFFFFC300);
const kCorpBlueDark = Color(0xFF0A3A7B); // gradiente header

enum RankMetric { xp, streak, streakGrua }

enum RankSubrol { bomberman, gruaman, general } // general: racha para todos

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  RankMetric _metric = RankMetric.xp;
  RankSubrol _subrol = RankSubrol.general; // por defecto General

  // ======= Helpers de Trophy.json (mostrar una sola vez por “racha de top1”) =======
  bool _trophyDialogOpen = false;

  String _currentKey() => '${_metric.name}_${_subrol.name}';

  Future<bool> _getWasTop1(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('wasTop1_$key') ?? false;
  }

  Future<void> _setWasTop1(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wasTop1_$key', value);
  }

  void _maybeShowTrophyOnce({required bool isMeTop1}) async {
    final key = _currentKey();
    final wasTop1 = await _getWasTop1(key);

    if (isMeTop1 && !wasTop1) {
      // Acaba de conseguir el top 1 → mostrar animación una vez
      if (mounted && !_trophyDialogOpen) {
        _trophyDialogOpen = true;
        await _setWasTop1(key, true); // marcar que ya fue mostrado

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: true,
            useSafeArea: true, // 👈 respeta barras de estado/gestos
            builder: (dialogContext) {
              final mq = MediaQuery.of(dialogContext);
              final size = mq.size;

              // Alto útil descontando safe areas y un margen para el insetPadding
              final safeHeight = size.height - mq.padding.vertical - 64;

              // Límites “sanos” para que quepa en pantallas pequeñas y no sea gigante en tablets
              final maxW = (size.width * 0.9).clamp(280.0, 520.0);
              final maxH = safeHeight.clamp(280.0, 520.0);

              // Tamaño de la animación dentro del diálogo
              final trophyH = (maxH * 0.45).clamp(120.0, 220.0);

              return Dialog(
                backgroundColor: Colors.white,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
                  // 👇 Si el contenido supera maxH, hace scroll en vez de desbordarse
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: trophyH,
                          child: Lottie.asset(
                            'lottie/Trophy.json',
                            repeat: false,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // (si quieres, limita el escalado para que no “engorde” demasiado)
                        MediaQuery(
                          data: mq.copyWith(
                            textScaleFactor: mq.textScaleFactor.clamp(1.0, 1.2),
                          ),
                          child: Column(
                            children: const [
                              Text(
                                '¡Eres #1!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: kCorpBlue,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                '¡Felicitaciones por liderar esta categoría! 🎉',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black,
                              backgroundColor: kCorpYellow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '¡Genial!',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ).whenComplete(() {
            _trophyDialogOpen = false;
          });
        });
      }
    } else if (!isMeTop1 && wasTop1) {
      // Si pierde el top 1, reseteamos para que la próxima vez vuelva a salir
      await _setWasTop1(key, false);
    }
  }

  // Etiqueta para el chip (título corto, con mayúsculas/tildes)
  String _metricChipLabel() {
    switch (_metric) {
      case RankMetric.xp:
        return 'XP';
      case RankMetric.streak:
        return 'Racha';
      case RankMetric.streakGrua:
        return 'Racha de grúa';
    }
  }

  // Texto formateado para el valor de la métrica
  String _metricValueText(num v) {
    final n = v.toInt();
    switch (_metric) {
      case RankMetric.xp:
        return '$n XP';
      case RankMetric.streak:
        return 'Racha $n';
      case RankMetric.streakGrua:
        return 'Racha de grúa $n';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('usuarios')
        .snapshots();

    return Scaffold(
      body: Container(
        // Fondo con gradiente azul → azul oscuro
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kCorpBlue, kCorpBlueDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ======= HEADER (responsive) =======
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          color: kCorpYellow,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ranking',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Spacer(),
                        _ChipBadge(
                          icon: Icons.leaderboard_rounded,
                          label: _metricChipLabel(),
                          pillColor: kCorpYellow,
                        ),
                      ],
                    ),
                  ),
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
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: _Filters(
                            metric: _metric,
                            subrol: _subrol,
                            onMetric: (m) => setState(() => _metric = m),
                            onSubrol: (s) => setState(() => _subrol = s),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: stream,
                          builder: (_, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: LoadingIndicator(
                                  message: 'Cargando ranking…',
                                ),
                              );
                            }
                            if (snap.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Error cargando el ranking:\n${snap.error}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              );
                            }

                            final users = (snap.data?.docs ?? []).map((d) {
                              final m = Map<String, dynamic>.from(d.data());
                              m.removeWhere((k, v) => v == null);
                              m['__id'] = d.id;
                              return m;
                            }).toList();

                            // Filtro por subrol (sin tocar valores de Firebase)
                            List<Map<String, dynamic>> filtered;
                            if (_subrol == RankSubrol.general) {
                              filtered = users; // racha general aplica a todos
                            } else {
                              final wanted = _subrol == RankSubrol.bomberman
                                  ? 'bomberman'
                                  : 'gruaman';
                              filtered = users
                                  .where(
                                    (u) => (u['subrol'] as String?) == wanted,
                                  )
                                  .toList();
                            }

                            // Campo según métrica
                            final metricKey = switch (_metric) {
                              RankMetric.xp => 'xp',
                              RankMetric.streak => 'streak',
                              RankMetric.streakGrua => 'streak_grua',
                            };

                            // Orden descendente por métrica
                            filtered.sort((a, b) {
                              final va = ((a[metricKey] ?? 0) as num)
                                  .toDouble();
                              final vb = ((b[metricKey] ?? 0) as num)
                                  .toDouble();
                              return vb.compareTo(va);
                            });

                            if (filtered.isEmpty) {
                              return const Center(
                                child: Text('No hay usuarios para ese filtro.'),
                              );
                            }

                            // UID logueado
                            final myUid =
                                FirebaseAuth.instance.currentUser?.uid;

                            // ¿El usuario logueado es #1 en la combinación actual?
                            bool isMeTop1 = false;
                            if (filtered.isNotEmpty && myUid != null) {
                              final top1Id = filtered.first['__id'] as String?;
                              isMeTop1 = (top1Id != null && top1Id == myUid);
                            }

                            // Trofeo (una sola vez por “racha” de top1)
                            _maybeShowTrophyOnce(isMeTop1: isMeTop1);

                            // Top 3 para podio
                            final podium = filtered.take(3).toList();
                            final rest = filtered.length > 3
                                ? filtered.sublist(3)
                                : <Map<String, dynamic>>[];

                            return CustomScrollView(
                              slivers: [
                                // Podio (responsive)
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1100,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          8,
                                          12,
                                          4,
                                        ),
                                        child: _Podium(
                                          metricKey: metricKey,
                                          users: podium,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Lista del resto (cada item con ancho máximo)
                                SliverList.separated(
                                  itemCount: rest.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (_, i) {
                                    final u = rest[i];
                                    final rank = i + 4; // después del top 3
                                    final id = u['__id'] as String;
                                    final nombre =
                                        (u['nombre'] ?? '') as String;
                                    final email = (u['email'] ?? '') as String;
                                    final subrol =
                                        (u['subrol'] as String?) ?? '-';
                                    final avatarUrl =
                                        (u['avatarUrl'] as String?) ?? '';
                                    final nivel = (u['nivel'] ?? 1) as int;
                                    final metricVal =
                                        (u[metricKey] ?? 0) as num;
                                    final isMe = myUid == id;

                                    ImageProvider? img;
                                    if (avatarUrl.isNotEmpty) {
                                      img = NetworkImage(avatarUrl);
                                    } else if (subrol == 'bomberman') {
                                      img = const NetworkImage(
                                        defaultBombermanUrl,
                                      );
                                    } else if (subrol == 'gruaman') {
                                      img = const NetworkImage(
                                        defaultGruamanUrl,
                                      );
                                    }

                                    return Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 1100,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Card(
                                            elevation: 0.5,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: ListTile(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              leading: CircleAvatar(
                                                radius: 22,
                                                backgroundImage: img,
                                                child: img == null
                                                    ? Text(
                                                        (nombre.isNotEmpty
                                                                ? nombre[0]
                                                                : (email.isNotEmpty
                                                                      ? email[0]
                                                                      : '?'))
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 16,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              title: Text(
                                                nombre.isNotEmpty
                                                    ? nombre
                                                    : (email.isNotEmpty
                                                          ? email
                                                          : id),
                                                maxLines: 2,
                                                overflow: TextOverflow.visible,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: isMe
                                                      ? kCorpBlue
                                                      : Colors.black87,
                                                ),
                                              ),
                                              subtitle: Row(
                                                children: [
                                                  _chip('Nivel $nivel'),
                                                  const SizedBox(width: 6),
                                                  if (isMe)
                                                    _chip('Tú', filled: true),
                                                ],
                                              ),
                                              trailing: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    _metricValueText(metricVal),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '#$rank',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 16),
                                ),
                              ],
                            );
                          },
                        ),
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

/// ====================== UI Helpers ======================

class _Filters extends StatelessWidget {
  final RankMetric metric;
  final RankSubrol subrol;
  final ValueChanged<RankMetric> onMetric;
  final ValueChanged<RankSubrol> onSubrol;

  const _Filters({
    required this.metric,
    required this.subrol,
    required this.onMetric,
    required this.onSubrol,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Subrol
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Subrol:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              _chipChoice(
                label: 'General',
                selected: subrol == RankSubrol.general,
                onTap: () => onSubrol(RankSubrol.general),
              ),
              _chipChoice(
                label: 'Bomberman',
                selected: subrol == RankSubrol.bomberman,
                onTap: () => onSubrol(RankSubrol.bomberman),
              ),
              _chipChoice(
                label: 'Gruaman',
                selected: subrol == RankSubrol.gruaman,
                onTap: () => onSubrol(RankSubrol.gruaman),
              ),
            ],
          ),
        ),
        // Métrica
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Métrica:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              _chipChoice(
                label: 'XP',
                selected: metric == RankMetric.xp,
                onTap: () => onMetric(RankMetric.xp),
              ),
              _chipChoice(
                label: 'Racha',
                selected: metric == RankMetric.streak,
                onTap: () => onMetric(RankMetric.streak),
              ),
              _chipChoice(
                label: 'Racha de grúa',
                selected: metric == RankMetric.streakGrua,
                onTap: () => onMetric(RankMetric.streakGrua),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kCorpYellow : const Color(0xFFF3F6FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? kCorpYellow : const Color(0xFFE3E8FF),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kCorpYellow.withOpacity(.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.black : kCorpBlue,
          ),
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  final String metricKey;
  final List<Map<String, dynamic>> users;

  const _Podium({required this.metricKey, required this.users});

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();

    // Estructura: [1°, 2°, 3°] si existen
    Widget tile(int pos) {
      if (pos - 1 >= users.length) return const SizedBox.shrink();
      final u = users[pos - 1];
      final nombre = (u['nombre'] ?? '') as String;
      final email = (u['email'] ?? '') as String;
      final subrol = (u['subrol'] as String?) ?? '-';
      final avatarUrl = (u['avatarUrl'] as String?) ?? '';
      final metricVal = (u[metricKey] ?? 0) as num;

      ImageProvider? img;
      if (avatarUrl.isNotEmpty) {
        img = NetworkImage(avatarUrl);
      } else if (subrol == 'bomberman') {
        img = const NetworkImage(defaultBombermanUrl);
      } else if (subrol == 'gruaman') {
        img = const NetworkImage(defaultGruamanUrl);
      }

      final medal = pos == 1
          ? '🥇'
          : pos == 2
          ? '🥈'
          : '🥉';
      final bg = pos == 1 ? kCorpYellow : const Color(0xFFF6FAFF);

      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5EAF8)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(medal, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 6),
              CircleAvatar(
                radius: 26,
                backgroundImage: img,
                child: img == null
                    ? Text(
                        (nombre.isNotEmpty
                                ? nombre[0]
                                : (email.isNotEmpty ? email[0] : '?'))
                            .toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                nombre.isNotEmpty ? nombre : (email.isNotEmpty ? email : '—'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${metricVal.toInt()}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: kCorpBlue,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (users.length >= 2) tile(2),
            tile(1),
            if (users.length >= 3) tile(3),
          ],
        ),
      ),
    );
  }
}

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
          const SizedBox(width: 2),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

Widget _chip(String label, {bool filled = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: filled ? kCorpYellow : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: filled ? kCorpYellow : Colors.grey.shade300),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: filled ? Colors.black : Colors.black87,
      ),
    ),
  );
}
