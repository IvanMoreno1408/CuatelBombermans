import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ImgbbService {
  /// [client] es inyectable para facilitar testing (por defecto usa [http.Client]).
  ImgbbService(this.apiKey, {http.Client? client}) : _client = client;

  final String apiKey;
  final http.Client? _client;

  /// Sube imagen (archivo) a ImgBB. Retorna el URL público (display_url o url).
  Future<String> uploadFile(
    File file, {
    String? name,
    int? expirationSeconds,
  }) async {
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);

    final uri = Uri.parse('https://api.imgbb.com/1/upload');
    final body = {
      'key': apiKey,
      'image': b64,
      if (name != null) 'name': name,
      if (expirationSeconds != null) 'expiration': expirationSeconds.toString(),
    };

    final client = _client ?? http.Client();
    final resp = await client.post(uri, body: body);
    if (resp.statusCode != 200) {
      throw Exception('ImgBB error HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final success = json['success'] == true;
    if (!success) {
      throw Exception('ImgBB subió pero no respondió success=true');
    }
    final data = json['data'] as Map<String, dynamic>;
    // Puedes usar display_url o url (ambas son públicas)
    return (data['display_url'] ?? data['url']) as String;
  }
}
