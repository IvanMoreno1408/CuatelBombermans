
import 'package:mockito/annotations.dart';

@GenerateMocks([FirebaseAuth, User])

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cuartel_bombermans/services/auth_service.dart';
import 'auth_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // No es necesario registrar fallback para String en mockito >= 5
  });
  group('AuthService', () {
    test('sendEmailVerification lanza si no hay usuario', () async {
      final mockAuth = MockFirebaseAuth();
      when(mockAuth.setLanguageCode(any)).thenAnswer((_) async {});
      when(mockAuth.currentUser).thenReturn(null);
      final svc = AuthService(auth: mockAuth);

      expect(() => svc.sendEmailVerification(), throwsA(isA<FirebaseAuthException>()));
    });

    test('sendEmailVerification llama a sendEmailVerification del usuario', () async {
      final mockAuth = MockFirebaseAuth();
      final mockUser = MockUser();
      when(mockAuth.setLanguageCode(any)).thenAnswer((_) async {});
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.sendEmailVerification()).thenAnswer((_) async {});
      final svc = AuthService(auth: mockAuth);

      await svc.sendEmailVerification();
      verify(mockUser.sendEmailVerification()).called(1);
    });
  });
}
