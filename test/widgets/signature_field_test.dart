import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cuartel_bombermans/widgets/signature_field.dart';

void main() {
  testWidgets('SignatureField calls onChanged with null when empty and save pressed', (tester) async {
    final changes = <Uint8List?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignatureField(
            label: 'Firma',
            onChanged: (v) => changes.add(v),
          ),
        ),
      ),
    );

    // Tap 'Guardar firma' when empty -> should notify with null
    expect(find.text('Guardar firma'), findsOneWidget);
    await tester.tap(find.text('Guardar firma'));
    await tester.pumpAndSettle();

    expect(changes.isNotEmpty, isTrue);
    expect(changes.last, isNull);

    // Tap 'Limpiar' also calls onChanged(null)
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    expect(changes.last, isNull);
  });
}
