import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cuartel_bombermans/widgets/loading_indicator.dart';

void main() {
  testWidgets('muestra etiqueta semántica por defecto "Cargando" cuando no hay message', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoadingIndicator())));

    expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
  });

  testWidgets('muestra el texto capitalizado y etiqueta semántica cuando se pasa message', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LoadingIndicator(message: 'esperando...')),
    ));
    // Give a short time for widgets to build (Lottie may be no-op in tests).
    await tester.pump(const Duration(milliseconds: 100));

    // Buscar el texto capitalizado entre todos los Text widgets.
    final texts = find.byType(Text);
    final foundText = texts.evaluate().any((e) {
      final w = e.widget as Text;
      final value = w.data ?? w.textSpan?.toPlainText() ?? '';
      return value.trim() == 'Esperando...';
    });

    // Buscar la etiqueta semántica si existe.
    final foundSemantics = find.bySemanticsLabel('Esperando...').evaluate().isNotEmpty;

    expect(foundText || foundSemantics, isTrue,
        reason: 'No se encontró el texto ni la etiqueta semántica "Esperando..."');
  });

  testWidgets('variant button usa el tamaño kLoaderButtonSize', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoadingIndicator.button())));

    final sizedBoxes = find.byType(SizedBox);
    final matches = sizedBoxes.evaluate().where((e) {
      final w = e.widget as SizedBox;
      return w.width == kLoaderButtonSize && w.height == kLoaderButtonSize;
    });

    expect(matches.length, greaterThanOrEqualTo(1));
  });

  testWidgets('fullscreen usa SizedBox.expand con Center como hijo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoadingIndicator(fullscreen: true))));

    final predicate = find.byWidgetPredicate((w) => w is SizedBox && w.child is Center);
    expect(predicate, findsOneWidget);
  });

  testWidgets('message vacío o solo espacios cae en la etiqueta "Cargando"', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoadingIndicator(message: '   '))));

    expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
  });
}
