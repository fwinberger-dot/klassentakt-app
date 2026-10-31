# Klassentakt – Mac-App

Dünne Hülle um klassentakt.ch (Electron). Klassentakt selbst wird weiter über klassentakt.ch aktualisiert; diese App muss nur neu gebaut werden, wenn sich die Hülle ändert.

## Bauen
- Jeder Push auf `main` baut die App auf GitHub (Reiter **Actions** → letzter Lauf → Artefakt **Klassentakt-mac**).
- Ein Tag `vX.Y.Z` erstellt zusätzlich ein Release mit `.dmg`.
- Lokal (auf einem Mac): `npm ci && npm start` (testen) bzw. `npm run dist:mac`.

## Installieren (ohne Apple-Signatur)
1. `.dmg` öffnen, Klassentakt in «Programme» ziehen.
2. Beim ersten Start: Systemeinstellungen → Datenschutz & Sicherheit → «Dennoch öffnen».
3. Meldet macOS «beschädigt»: Terminal → `xattr -cr /Applications/Klassentakt.app`

## Update-Hinweis
Die App liest `https://klassentakt.ch/app/version.json`:
```json
{ "mac": { "version": "0.1.1", "url": "https://…/Klassentakt-0.1.1.dmg", "notes": "Was neu ist" } }
```

## Brücke
In der Hülle gibt es `window.klassentaktShell` (`isShell`, `platform`, `shellVersion`, `features`). Die Web-App blendet App-Funktionen nur ein, wenn es existiert.
