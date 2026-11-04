# Klassentakt – Mac-App

Dünne Hülle um klassentakt.ch (Electron). Klassentakt selbst wird weiter über klassentakt.ch aktualisiert; diese App muss nur neu gebaut werden, wenn sich die Hülle ändert.

## Bauen
- Jeder Push auf `main` baut die App auf GitHub (Reiter **Actions** → letzter Lauf), signiert mit Developer ID und notarisiert.
  - Artefakt **Klassentakt-download**: `Klassentakt-mac.dmg`, `Klassentakt-mac.zip`, `latest.json` → entpacken und mit `ops/download.sh staging|prod <ordner>` (Web-Repo) nach `/download/` hochladen.
  - Ist die Version in `package.json` neu, entsteht zusätzlich ein GitHub-Release (nur noch für Apps bis 0.4.0).
- Lokal (auf einem Mac): `npm ci && npm start` (testen), `npm test`, `npm run dist:mac`.

## Verteilen an Lehrpersonen
Download-Knopf im Personen-Menü der Web-App → `https://klassentakt.ch/download/mac` (302 auf `Klassentakt-mac.dmg`). Braucht macOS 13 oder neuer.

## Selbst-Update
Die App liest `https://klassentakt.ch/download/latest.json` (öffentlich, ohne Login):
```json
{ "version": "0.4.1", "notes": "…", "url": "Klassentakt-mac.zip", "sha256": "…", "sha512": "…", "size": 123,
  "dmg": { "url": "Klassentakt-mac.dmg", "sha256": "…", "sha512": "…", "size": 456 }, "date": "…" }
```
`url` ist relativ zu `/download/` und muss auf demselben Server liegen; das zip wird per SHA-256 geprüft.
Zum Testen gegen staging die App aus dem Terminal starten:
`KLASSENTAKT_UPDATE_BASE=https://staging.klassentakt.ch/download/ /Applications/Klassentakt.app/Contents/MacOS/Klassentakt`

## Brücke
In der Hülle gibt es `window.klassentaktShell` (`isShell`, `platform`, `shellVersion`, `features`). Die Web-App blendet App-Funktionen nur ein, wenn es existiert.

## Update-Text («Was ist neu»)
Standard: kein Text im Update-Fenster. Soll eine neue Funktion angepriesen werden, in NEU.txt schreiben:

```
Version 0.4.1
- Neue Funktion XY
```

Die erste Zeile muss genau zur Version in package.json passen, sonst wird nichts angezeigt.
