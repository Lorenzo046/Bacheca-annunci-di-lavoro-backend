import 'dart:io';

import 'package:bacheca_annunci_backend/database.dart';
import 'package:bacheca_annunci_backend/server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main(List<String> args) async {
  final porta = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  final db = Database('data/db.json')..carica();
  final uploads = Directory('uploads')..createSync(recursive: true);

  final api = Api(db, uploads.path);

  // 0.0.0.0 = in ascolto su tutte le interfacce, così lo smartphone
  // collegato alla stessa rete Wi-Fi può raggiungere il server.
  final server = await io.serve(api.handler, InternetAddress.anyIPv4, porta);
  print('Server in ascolto sulla porta ${server.port}');

  for (final interfaccia in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final indirizzo in interfaccia.addresses) {
      print('  -> http://${indirizzo.address}:${server.port}  (${interfaccia.name})');
    }
  }
}
