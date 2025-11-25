import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cuartel_bombermans/services/imgbb_service.dart';

void main() {
  group('ImgbbService', () {
    late File tmpFile;

    setUp(() async {
      tmpFile = File('test/tmp_image.bin');
      await tmpFile.writeAsBytes(List<int>.generate(10, (i) => i));
    });

    tearDown(() async {
      if (await tmpFile.exists()) await tmpFile.delete();
    });

    test('retorna URL cuando la API responde success=true', () async {
      final fakeResponse = jsonEncode({
        'success': true,
        'data': {'display_url': 'https://imgbb.example/image.png'}
      });

      final client = MockClient((request) async {
        return http.Response(fakeResponse, 200);
      });

      final svc = ImgbbService('DUMMY_KEY', client: client);
      final url = await svc.uploadFile(tmpFile, name: 'x');

      expect(url, 'https://imgbb.example/image.png');
    });

    test('lanza cuando el statusCode != 200', () async {
      final client = MockClient((request) async {
        return http.Response('err', 500);
      });

      final svc = ImgbbService('DUMMY_KEY', client: client);

      await expectLater(svc.uploadFile(tmpFile), throwsA(isA<Exception>()));
    });

    test('lanza cuando success=false en el body', () async {
      final fakeResponse = jsonEncode({'success': false, 'data': {}});
      final client = MockClient((request) async {
        return http.Response(fakeResponse, 200);
      });

      final svc = ImgbbService('DUMMY_KEY', client: client);
      await expectLater(svc.uploadFile(tmpFile), throwsA(isA<Exception>()));
    });
  });
}
