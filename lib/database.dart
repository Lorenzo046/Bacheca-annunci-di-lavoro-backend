import 'dart:convert';
import 'dart:io';

/// "Database" minimale: tutti i dati vengono tenuti in memoria e salvati
/// in un file JSON (data/db.json) a ogni modifica.
class Database {
  final File _file;

  List<Map<String, dynamic>> aziende = [];
  List<Map<String, dynamic>> annunci = [];
  List<Map<String, dynamic>> candidature = [];

  /// token di sessione -> id azienda
  Map<String, int> sessioni = {};

  int _prossimoId = 1;

  Database(String percorso) : _file = File(percorso);

  void carica() {
    if (!_file.existsSync()) {
      _file.parent.createSync(recursive: true);
      salva();
      return;
    }
    final dati = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    aziende = List<Map<String, dynamic>>.from(dati['aziende'] ?? []);
    annunci = List<Map<String, dynamic>>.from(dati['annunci'] ?? []);
    candidature = List<Map<String, dynamic>>.from(dati['candidature'] ?? []);
    sessioni = Map<String, int>.from(dati['sessioni'] ?? {});
    _prossimoId = dati['prossimoId'] ?? 1;
  }

  void salva() {
    final dati = {
      'aziende': aziende,
      'annunci': annunci,
      'candidature': candidature,
      'sessioni': sessioni,
      'prossimoId': _prossimoId,
    };
    _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(dati));
  }

  int nuovoId() => _prossimoId++;
}
