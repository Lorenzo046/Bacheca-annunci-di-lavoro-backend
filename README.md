# Bacheca Annunci di Lavoro – Back-end

Server REST scritto in **Dart** con [shelf](https://pub.dev/packages/shelf).
I dati sono salvati in un file JSON (`data/db.json`) e i curriculum nella cartella `uploads/`.

## Avvio

```bash
dart pub get
dart run bin/main.dart
```

All'avvio il server stampa gli indirizzi IP del computer: usate quello della rete Wi-Fi
(es. `http://192.168.1.10:8080`) nell'app Flutter. Smartphone e PC devono essere sulla stessa rete.
Se il telefono non riesce a collegarsi, controllate che il firewall di Windows consenta Dart sulle reti private.

Porta diversa: `PORT=9000 dart run bin/main.dart`.

## API

| Metodo | Endpoint | Auth | Descrizione | Req. |
|---|---|---|---|---|
| POST | `/api/registrazione` | – | Crea un account azienda (`nome`, `email`, `password`) | R1 |
| POST | `/api/login` | – | Restituisce un token di sessione | R2 |
| POST | `/api/logout` | ✔ | Invalida il token | R3 |
| POST | `/api/annunci` | ✔ | Pubblica un annuncio (`titolo`, `descrizione`, `sede`) | R4 |
| GET | `/api/annunci` | – | Elenco annunci (bacheca) | R5 |
| GET | `/api/annunci/{id}` | – | Dettaglio annuncio | R5 |
| POST | `/api/annunci/{id}/candidature` | – | Candidatura multipart: `nome`, `cognome`, `email`, `messaggio`, file `cv` | R6 |
| GET | `/api/miei-annunci` | ✔ | Annunci dell'azienda con numero di candidature | R7 |
| GET | `/api/annunci/{id}/candidature` | ✔ | Candidature di un proprio annuncio | R7 |
| GET | `/api/candidature/{id}/cv` | ✔ | Scarica il curriculum | R7 |

Le richieste autenticate usano l'header `Authorization: Bearer <token>`.
Le password sono salvate come hash SHA-256 con salt.
