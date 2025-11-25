import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:cuartel_bombermans/screens/login_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App e2e smoke: Login screen visible', (tester) async {
    // This is a smoke e2e test that simply boots the LoginScreen and
    // verifies the main title is present. For a full e2e (with Firebase)
    // run against Firebase Emulator or provide mocks.
    await tester.pumpWidget(MaterialApp(home: const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
