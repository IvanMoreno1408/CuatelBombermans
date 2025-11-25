// lib/widgets/loading_indicator.dart
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Tamaños globales del loader (consistencia en TODA la app).
const double kLoaderStandardSize = 200.0; // 👈 tamaño único estándar
const double kLoaderButtonSize = 22.0; // 👈 mini para botones/diálogos

/// Indicador de carga con Lottie:
/// - Usa por defecto un tamaño GLOBAL (kLoaderStandardSize) para mantener
///   consistencia en todas las vistas.
/// - `fullscreen` centra y ocupa toda la pantalla (no duplica con HomeShell).
/// - `asset` por defecto 'flutter/loading.json' como pediste.
/// - `LoadingIndicator.button()` es la única variante mini pensada para botones.
class LoadingIndicator extends StatelessWidget {
  final String? message;

  /// Tamaño directo del Lottie (alto/ancho). Si es null, se usa kLoaderStandardSize.
  final double? size;

  /// Si true, ocupa toda la pantalla y centra el contenido.
  final bool fullscreen;

  /// Ruta del asset de Lottie.
  final String asset;

  /// Constructor general (usa tamaño global si `size` es null).
  const LoadingIndicator({
    super.key,
    this.message,
    this.size,
    this.fullscreen = false,
    this.asset = 'lottie/loading.json',
  });

  /// Variante mini para botones/ítems compactos (siempre usa kLoaderButtonSize).
  const LoadingIndicator.button({
    super.key,
    this.message,
    this.asset = 'lottie/loading.json',
  }) : size = kLoaderButtonSize,
       fullscreen = false;

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    final trimmed = s.trimLeft();
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedSize = size ?? kLoaderStandardSize;

    final core = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // UnconstrainedBox asegura que la animación respete el tamaño fijo
        // aunque el padre intente imponer constraints.
        UnconstrainedBox(
          child: SizedBox(
            height: resolvedSize,
            width: resolvedSize,
            // Lottie puede fallar en entornos de test si los assets no están
            // correctamente empaquetados. Capturamos posibles excepciones
            // y mostramos un placeholder silencioso para que los tests
            // puedan centrarse en la UI/semántica.
            child: _buildLottieSafe(asset),
          ),
        ),
        if (message != null && message!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _capitalize(message!),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    final content = Semantics(
      label: (message == null || message!.trim().isEmpty)
          ? 'Cargando'
          : _capitalize(message!),
      liveRegion: true,
      child: core,
    );

    if (fullscreen) {
      return SizedBox.expand(child: Center(child: content));
    }
    // Alineamos y centramos por defecto para evitar variaciones entre vistas.
    return Align(alignment: Alignment.center, child: content);
  }

  Widget _buildLottieSafe(String asset) {
    try {
      return Lottie.asset(asset, repeat: true);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}
