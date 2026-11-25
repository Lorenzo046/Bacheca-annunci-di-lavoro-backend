import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'database.dart';

/// Contiene tutte le API REST del back-end.
class Api {
  final Database db;
  final String cartellaUploads;

  Api(this.db, this.cartellaUploads);

  Handler get handler {
    final router = Router()
      // Autenticazione azienda (R1, R2, R3)
      ..post('/api/registrazione', _registrazione)
      ..post('/api/login', _login)
      ..post('/api/logout', _logout)
      // Bacheca pubblica (R5)
      ..get('/api/annunci', _elencoAnnunci)
      ..get('/api/annunci/<id|[0-9]+>', _dettaglioAnnuncio)
      // Pubblicazione annuncio (R4)
      ..post('/api/annunci', _creaAnnuncio)
      // Candidatura (R6)
      ..post('/api/annunci/<id|[0-9]+>/candidature', _candidati)
      // Area riservata: candidature ricevute (R7)
      ..get('/api/miei-annunci', _mieiAnnunci)
      ..get('/api/annunci/<id|[0-9]+>/candidature', _candidatureAnnuncio)
      ..get('/api/candidature/<id|[0-9]+>/cv', _scaricaCv);

    return const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_cors)
        .addHandler(router.call);
  }

  /// Permette di provare l'app anche dal browser (Flutter web).
  /// Sullo smartphone non serve, ma non dà fastidio.
  static Handler _cors(Handler inner) {
    const headers = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
    return (request) async {
      if (request.method == 'OPTIONS') return Response.ok(null, headers: headers);
      final response = await inner(request);
      return response.change(headers: headers);
    };
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  Response _json(Object dati, {int status = 200}) => Response(status,
      body: jsonEncode(dati),
      headers: {'content-type': 'application/json; charset=utf-8'});

  Response _errore(String messaggio, {int status = 400}) =>
      _json({'errore': messaggio}, status: status);

  String _hashPassword(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  String _generaToken() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  bool _emailValida(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  /// Restituisce l'azienda autenticata (dall'header `Authorization: Bearer <token>`)
  /// oppure null se il token manca o non è valido.
  /// Se [ancheDaUrl] è true il token può arrivare anche come parametro
  /// `?token=` (serve per aprire il curriculum direttamente nel browser).
  Map<String, dynamic>? _aziendaAutenticata(Request request, {bool ancheDaUrl = false}) {
    final header = request.headers['authorization'] ?? '';
    String? token;
    if (header.startsWith('Bearer ')) {
      token = header.substring(7);
    } else if (ancheDaUrl) {
      token = request.url.queryParameters['token'];
    }
    if (token == null) return null;
    final idAzienda = db.sessioni[token];
    if (idAzienda == null) return null;
    return db.aziende.firstWhere((a) => a['id'] == idAzienda);
  }

  Map<String, dynamic>? _trovaAnnuncio(String id) {
    final idNum = int.parse(id);
    for (final a in db.annunci) {
      if (a['id'] == idNum) return a;
    }
    return null;
  }

  Map<String, dynamic> _annuncioPubblico(Map<String, dynamic> annuncio) {
    final azienda = db.aziende.firstWhere((a) => a['id'] == annuncio['aziendaId']);
    return {...annuncio, 'nomeAzienda': azienda['nome']};
  }

  Future<Map<String, dynamic>?> _leggiJson(Request request) async {
    try {
      return jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // R1 - Registrazione
  // ---------------------------------------------------------------------------
  Future<Response> _registrazione(Request request) async {
    final body = await _leggiJson(request);
    if (body == null) return _errore('Richiesta non valida');

    final nome = (body['nome'] ?? '').toString().trim();
    final email = (body['email'] ?? '').toString().trim().toLowerCase();
    final password = (body['password'] ?? '').toString();

    if (nome.isEmpty) return _errore('Il nome dell\'azienda è obbligatorio');
    if (!_emailValida(email)) return _errore('Email non valida');
    if (password.length < 6) {
      return _errore('La password deve avere almeno 6 caratteri');
    }
    if (db.aziende.any((a) => a['email'] == email)) {
      return _errore('Esiste già un account con questa email', status: 409);
    }

    final salt = _generaToken();
    final azienda = {
      'id': db.nuovoId(),
      'nome': nome,
      'email': email,
      'salt': salt,
      'passwordHash': _hashPassword(password, salt),
    };
    db.aziende.add(azienda);
    db.salva();
    return _json({'id': azienda['id'], 'nome': nome, 'email': email}, status: 201);
  }

  // ---------------------------------------------------------------------------
  // R2 - Login
  // ---------------------------------------------------------------------------
  Future<Response> _login(Request request) async {
    final body = await _leggiJson(request);
    if (body == null) return _errore('Richiesta non valida');

    final email = (body['email'] ?? '').toString().trim().toLowerCase();
    final password = (body['password'] ?? '').toString();

    Map<String, dynamic>? azienda;
    for (final a in db.aziende) {
      if (a['email'] == email) azienda = a;
    }
    if (azienda == null ||
        _hashPassword(password, azienda['salt']) != azienda['passwordHash']) {
      return _errore('Email o password errati', status: 401);
    }

    final token = _generaToken();
    db.sessioni[token] = azienda['id'];
    db.salva();
    return _json({
      'token': token,
      'azienda': {'id': azienda['id'], 'nome': azienda['nome'], 'email': azienda['email']},
    });
  }

  // ---------------------------------------------------------------------------
  // R3 - Logout: il token viene invalidato lato server
  // ---------------------------------------------------------------------------
  Response _logout(Request request) {
    final header = request.headers['authorization'] ?? '';
    if (header.startsWith('Bearer ')) {
      db.sessioni.remove(header.substring(7));
      db.salva();
    }
    return _json({'messaggio': 'Logout effettuato'});
  }

  // ---------------------------------------------------------------------------
  // R5 - Bacheca
  // ---------------------------------------------------------------------------
  Response _elencoAnnunci(Request request) {
    final elenco = db.annunci.map(_annuncioPubblico).toList().reversed.toList();
    return _json(elenco);
  }

  Response _dettaglioAnnuncio(Request request, String id) {
    final annuncio = _trovaAnnuncio(id);
    if (annuncio == null) return _errore('Annuncio non trovato', status: 404);
    return _json(_annuncioPubblico(annuncio));
  }

  // ---------------------------------------------------------------------------
  // R4 - Pubblicazione annuncio
  // ---------------------------------------------------------------------------
  Future<Response> _creaAnnuncio(Request request) async {
    final azienda = _aziendaAutenticata(request);
    if (azienda == null) return _errore('Non autenticato', status: 401);

    final body = await _leggiJson(request);
    if (body == null) return _errore('Richiesta non valida');

    final titolo = (body['titolo'] ?? '').toString().trim();
    final descrizione = (body['descrizione'] ?? '').toString().trim();
    final sede = (body['sede'] ?? '').toString().trim();
    if (titolo.isEmpty || descrizione.isEmpty) {
      return _errore('Titolo e descrizione sono obbligatori');
    }

    final annuncio = {
      'id': db.nuovoId(),
      'aziendaId': azienda['id'],
      'titolo': titolo,
      'descrizione': descrizione,
      'sede': sede,
      'dataPubblicazione': DateTime.now().toIso8601String(),
    };
    db.annunci.add(annuncio);
    db.salva();
    return _json(_annuncioPubblico(annuncio), status: 201);
  }

  // ---------------------------------------------------------------------------
  // R6 - Candidatura (multipart/form-data con il file del curriculum)
  // ---------------------------------------------------------------------------
  Future<Response> _candidati(Request request, String id) async {
    final annuncio = _trovaAnnuncio(id);
    if (annuncio == null) return _errore('Annuncio non trovato', status: 404);

    final contentType = request.headers['content-type'];
    if (contentType == null) return _errore('Richiesta non valida');
    final mediaType = MediaType.parse(contentType);
    final boundary = mediaType.parameters['boundary'];
    if (mediaType.mimeType != 'multipart/form-data' || boundary == null) {
      return _errore('La richiesta deve essere multipart/form-data');
    }

    final campi = <String, String>{};
    List<int>? fileBytes;
    String? nomeFile;

    final parti = MimeMultipartTransformer(boundary).bind(request.read());
    await for (final parte in parti) {
      final disposizione = HeaderValue.parse(
          parte.headers['content-disposition'] ?? '',
          parameterSeparator: ';');
      final nomeCampo = disposizione.parameters['name'];
      final filename = disposizione.parameters['filename'];
      final bytes = await parte.fold<List<int>>([], (acc, b) => acc..addAll(b));
      if (filename != null && nomeCampo == 'cv') {
        nomeFile = filename;
        fileBytes = bytes;
      } else if (nomeCampo != null) {
        campi[nomeCampo] = utf8.decode(bytes).trim();
      }
    }

    final nome = campi['nome'] ?? '';
    final cognome = campi['cognome'] ?? '';
    final email = (campi['email'] ?? '').toLowerCase();
    if (nome.isEmpty || cognome.isEmpty) {
      return _errore('Nome e cognome sono obbligatori');
    }
    if (!_emailValida(email)) return _errore('Email non valida');
    if (fileBytes == null || fileBytes.isEmpty || nomeFile == null) {
      return _errore('Il curriculum è obbligatorio');
    }
    final estensione = p.extension(nomeFile).toLowerCase();
    if (!['.pdf', '.doc', '.docx'].contains(estensione)) {
      return _errore('Il curriculum deve essere un file PDF, DOC o DOCX');
    }
    if (fileBytes.length > 10 * 1024 * 1024) {
      return _errore('Il curriculum non può superare i 10 MB');
    }

    // Il file viene salvato con un nome generato dal server (mai quello del client)
    final idCandidatura = db.nuovoId();
    final nomeSalvato = 'cv_$idCandidatura$estensione';
    await File(p.join(cartellaUploads, nomeSalvato)).writeAsBytes(fileBytes);

    final candidatura = {
      'id': idCandidatura,
      'annuncioId': annuncio['id'],
      'nome': nome,
      'cognome': cognome,
      'email': email,
      'messaggio': campi['messaggio'] ?? '',
      'cvNomeOriginale': p.basename(nomeFile),
      'cvFile': nomeSalvato,
      'dataInvio': DateTime.now().toIso8601String(),
    };
    db.candidature.add(candidatura);
    db.salva();
    return _json({'messaggio': 'Candidatura inviata', 'id': idCandidatura}, status: 201);
  }

  // ---------------------------------------------------------------------------
  // R7 - Consultazione candidature (solo per l'azienda proprietaria)
  // ---------------------------------------------------------------------------
  Response _mieiAnnunci(Request request) {
    final azienda = _aziendaAutenticata(request);
    if (azienda == null) return _errore('Non autenticato', status: 401);

    final miei = db.annunci
        .where((a) => a['aziendaId'] == azienda['id'])
        .map((a) => {
              ..._annuncioPubblico(a),
              'numeroCandidature':
                  db.candidature.where((c) => c['annuncioId'] == a['id']).length,
            })
        .toList()
        .reversed
        .toList();
    return _json(miei);
  }

  Response _candidatureAnnuncio(Request request, String id) {
    final azienda = _aziendaAutenticata(request);
    if (azienda == null) return _errore('Non autenticato', status: 401);
    final annuncio = _trovaAnnuncio(id);
    if (annuncio == null) return _errore('Annuncio non trovato', status: 404);
    if (annuncio['aziendaId'] != azienda['id']) {
      return _errore('Non puoi vedere le candidature di questo annuncio', status: 403);
    }
    final elenco = db.candidature.where((c) => c['annuncioId'] == annuncio['id']).toList();
    return _json(elenco);
  }

  Future<Response> _scaricaCv(Request request, String id) async {
    final azienda = _aziendaAutenticata(request, ancheDaUrl: true);
    if (azienda == null) return _errore('Non autenticato', status: 401);

    final idNum = int.parse(id);
    Map<String, dynamic>? candidatura;
    for (final c in db.candidature) {
      if (c['id'] == idNum) candidatura = c;
    }
    if (candidatura == null) return _errore('Candidatura non trovata', status: 404);
    final annuncio = _trovaAnnuncio(candidatura['annuncioId'].toString());
    if (annuncio == null || annuncio['aziendaId'] != azienda['id']) {
      return _errore('Accesso negato', status: 403);
    }

    final file = File(p.join(cartellaUploads, candidatura['cvFile']));
    if (!file.existsSync()) return _errore('File non trovato', status: 404);
    return Response.ok(file.openRead(), headers: {
      'content-type': lookupMimeType(file.path) ?? 'application/octet-stream',
      'content-length': file.lengthSync().toString(),
      'content-disposition': 'inline; filename="${candidatura['cvFile']}"',
    });
  }
}
