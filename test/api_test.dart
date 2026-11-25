import 'dart:convert';
import 'dart:io';

import 'package:bacheca_annunci_backend/database.dart';
import 'package:bacheca_annunci_backend/server.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

/// Esegue i tre scenari S1-S3 contro un server avviato su una cartella temporanea.
void main() {
  late HttpServer server;
  late Directory tmp;
  late String base;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bacheca_test');
    final db = Database('${tmp.path}/db.json')..carica();
    final uploads = Directory('${tmp.path}/uploads')..createSync();
    server = await io.serve(Api(db, uploads.path).handler, 'localhost', 0);
    base = 'http://localhost:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Future<http.Response> postJson(String path, Map body, {String? token}) => http.post(
        Uri.parse('$base$path'),
        headers: {'content-type': 'application/json', 'authorization': 'Bearer ${token ?? ''}'},
        body: jsonEncode(body),
      );

  test('scenari S1, S2, S3', () async {
    // S1 - registrazione, login, pubblicazione
    var r = await postJson('/api/registrazione',
        {'nome': 'Acme Srl', 'email': 'hr@acme.it', 'password': 'segreta1'});
    expect(r.statusCode, 201);
    r = await postJson('/api/registrazione',
        {'nome': 'Acme Srl', 'email': 'hr@acme.it', 'password': 'segreta1'});
    expect(r.statusCode, 409); // email duplicata

    r = await postJson('/api/login', {'email': 'hr@acme.it', 'password': 'sbagliata'});
    expect(r.statusCode, 401);
    r = await postJson('/api/login', {'email': 'hr@acme.it', 'password': 'segreta1'});
    expect(r.statusCode, 200);
    final token = jsonDecode(r.body)['token'] as String;

    r = await postJson('/api/annunci', {'titolo': 'X', 'descrizione': 'Y'});
    expect(r.statusCode, 401); // senza token
    r = await postJson('/api/annunci',
        {'titolo': 'Sviluppatore Flutter', 'descrizione': 'Cerchiamo...', 'sede': 'Salerno'},
        token: token);
    expect(r.statusCode, 201);
    final annuncioId = jsonDecode(r.body)['id'];

    // S2 - bacheca e candidatura (senza login)
    r = await http.get(Uri.parse('$base/api/annunci'));
    final bacheca = jsonDecode(r.body) as List;
    expect(bacheca.single['titolo'], 'Sviluppatore Flutter');
    expect(bacheca.single['nomeAzienda'], 'Acme Srl');

    final pdf = utf8.encode('%PDF-1.4 finto curriculum');
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/annunci/$annuncioId/candidature'))
      ..fields.addAll({'nome': 'Mario', 'cognome': 'Rossi', 'email': 'mario@rossi.it'})
      ..files.add(http.MultipartFile.fromBytes('cv', pdf, filename: 'cv mario.pdf'));
    r = await http.Response.fromStream(await req.send());
    expect(r.statusCode, 201, reason: r.body);

    // S3 - consultazione candidature, CV, logout
    final auth = {'authorization': 'Bearer $token'};
    r = await http.get(Uri.parse('$base/api/miei-annunci'), headers: auth);
    expect((jsonDecode(r.body) as List).single['numeroCandidature'], 1);

    r = await http.get(Uri.parse('$base/api/annunci/$annuncioId/candidature'), headers: auth);
    final candidatura = (jsonDecode(r.body) as List).single;
    expect(candidatura['cognome'], 'Rossi');

    r = await http.get(Uri.parse('$base/api/candidature/${candidatura['id']}/cv'), headers: auth);
    expect(r.statusCode, 200);
    expect(r.bodyBytes, pdf);
    expect(r.headers['content-type'], 'application/pdf');
    // apertura dal browser con il token nell'URL
    r = await http.get(Uri.parse('$base/api/candidature/${candidatura['id']}/cv?token=$token'));
    expect(r.statusCode, 200);
    r = await http.get(Uri.parse('$base/api/candidature/${candidatura['id']}/cv'));
    expect(r.statusCode, 401);

    r = await postJson('/api/logout', {}, token: token);
    expect(r.statusCode, 200);
    r = await http.get(Uri.parse('$base/api/miei-annunci'), headers: auth);
    expect(r.statusCode, 401); // area riservata non più accessibile
  });
}
