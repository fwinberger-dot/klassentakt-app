# Brücke iPad-App ↔ Web-App, Paket A (Stand 04.11.2026)

Rolle «Apple-Apps» für die Rolle «Web-App». Die App-Seite ist auf dem Branch `claude/ipad-paket-a-cae7e1` gebaut (`ios/Klassentakt/Bridge.swift`). In `web/index.html` ist **nichts** geändert. Jede Funktion läuft auch ohne Web-Anschluss, mit dem Rückfall, der unten pro Funktion beschrieben ist. Die Anschlüsse machen das Ganze nur runder.

## Grundlagen

Die App setzt `window.klassentaktShell` nur auf `klassentakt.ch` und `*.klassentakt.ch`, und zwar vor dem ersten Script der Seite (Hauptframe). Im Screen-Fenster (`about:blank` + `document.write`) gibt es die Brücke nicht. Dort gilt wie bisher `ktShell()` → `window.opener.klassentaktShell`.

```js
klassentaktShell = {
  isShell: true, platform: 'ios', shellVersion: '1.0.0',
  features: ['beamer-extern','shortcuts','scan','camera','beamer-layer','share','print','files'],
  send(name, payload),        // Web → App, payload = einfaches JSON-Objekt
  on(name, fn) → off(),       // App → Web, fn(payload)
  share({ name, type, blob }) → Promise,  // Helfer: liest blob als Base64 und schickt 'share'
  print({ name, type, blob }) → Promise,  // Helfer: dito für 'print'
}
```

- **Anmelden = zuhören.** `on(name, fn)` meldet der App: «diese Seite kann `name`». Ohne Anmeldung nimmt die App ihren Rückfall. `off()` (der Rückgabewert) meldet wieder ab, ein Neuladen ebenfalls.
- Jedes Ereignis kommt zusätzlich als `window` CustomEvent `klassentakt-shell` mit `detail: {name, payload}`, zum Mitlesen ohne Anmeldung.
- Das bisherige Ereignis `klassentakt-beamer` (`{open, extern}`) bleibt unverändert.
- Erkennen: `sh.platform === 'ios' && sh.features.includes('scan')` usw. Die Mac-App hat andere `features`, `send`/`on` gibt es dort nicht.
- Nachrichten aus iframes (YouTube usw.) nimmt die App nicht an.
- Das iPad hat kein `sh.beamer` (das ist die Mac-API). Das ist Absicht, damit das bestehende Menü «Auf anderen Bildschirm» nicht erscheint.

## 1. Dokumentenkamera

| Richtung | Name | Nutzlast |
|---|---|---|
| Web → App | `camera` | `{open?: boolean}` (Standard `true`, `false` schliesst) |
| App → Web | `file` | `{source: 'camera', name: 'Dokumentenkamera 2026-11-04 09.41.jpg', type: 'image/jpeg', size, file: File}` |
| App → Web | `beamer` | Zustand, darin `camera: true/false` (siehe 2.) |

Was die App tut: Sie zeigt das Live-Bild auf dem Beamer (über dem Screen), Vorschau und Knöpfe auf dem iPad, Zoom mit zwei Fingern, Einfrieren, Drehen, Licht und «Foto übernehmen». Öffnen geht über das Kürzel ⌘⇧K, den Knopf «Beamer» und die Auswahl beim Verbinden.

**Web-Anschluss:**
1. Knopf «Dokumentenkamera» im Classroom Screen bzw. im Menü, sichtbar bei `features.includes('camera')` → `send('camera')`.
2. `on('file', …)`: `source === 'camera'` → Foto in die aktuelle Lektion bzw. den Ablauf hängen (gleicher Weg wie «Datei hochladen», mit Rückmeldung).

**Rückfall ohne Anschluss:** Die Kamera geht über ⌘⇧K oder den Knopf «Beamer». «Foto übernehmen» öffnet eine Vorschau mit Teilen-Menü (In Dateien sichern, Bild sichern, AirDrop, Drucken) und dem Hinweis, dass diese Klassentakt-Version das noch nicht direkt übernimmt.

## 2. Beamer-Ebene

| Richtung | Name | Nutzlast |
|---|---|---|
| Web → App | `overlay` | `{timer?: {action: 'start'\|'pause'\|'resume'\|'toggle'\|'reset', seconds?: number}, black?: boolean, quiet?: boolean}` |
| Web → App | `beamerPanel` | `{}`: öffnet die Fernbedienung auf dem iPad |
| App → Web | `beamer` | `{open, extern, black, camera, timer: {state: 'idle'\|'running'\|'paused'\|'done', remaining, duration}, quiet: false\|'gruen'\|'gelb'\|'rot'}` |

Was die App tut: Sie hat eine eigene Ebene auf dem externen Bildschirm. Von unten nach oben: Screen, Kamera, Timer (oben rechts), Ruhe-Ampel (unten rechts), schwarz. Beim Verbinden (HDMI oder AirPlay «erweitern») erscheinen ein Hinweis und eine Auswahl: Classroom Screen, Dokumentenkamera, schwarz oder später. Unten rechts auf dem iPad gibt es den Knopf «Beamer» als Fernbedienung (Timer 1–15 Min., Start/Pause, Ampel mit Empfindlichkeit, schwarz). Die Ampel misst nur den Pegel, nimmt nichts auf und mischt mit Musik und Videos.

**Web-Anschluss (optional):**
- Wer den Timer der Ebene statt des Screen-Timers nutzen will: `send('overlay', {timer: {action: 'start', seconds: 300}})`.
- Den Zustand anzeigen, z. B. «Beamer schwarz» im Screen-Menü: `on('beamer', st => …)`.
- Knopf «Fernbedienung» im Screen-Menü bei `features.includes('beamer-layer')` → `send('beamerPanel')`.

**Rückfall ohne Anschluss:** Alles läuft nativ über den Knopf «Beamer» und die Kürzel. Der Timer der Web-App (im Screen) und der Timer der Ebene sind dann zwei getrennte Timer. Das ist bewusst so, siehe 4.

## 3. Scanner

| Richtung | Name | Nutzlast |
|---|---|---|
| Web → App | `scan` | `{format?: 'pdf'\|'image'}`: ohne Format fragt die App nach dem Scannen |
| App → Web | `file` | `{source: 'scan', name: 'Scan 2026-11-04 09.41.pdf', type: 'application/pdf'\|'image/jpeg', size, file: File}`. Bei `image` und mehreren Seiten kommt ein Ereignis pro Seite, `… (2).jpg` |

Was die App tut: Sie öffnet den VisionKit-Scanner (zuschneiden, entzerren, mehrere Seiten). Die Seiten werden auf höchstens 2200 px verkleinert, das PDF ist A4 hoch oder quer, JPEG mit 75 %.

**Web-Anschluss:**
1. Neben «Datei hochladen» (Lektion, Material) einen Knopf «Scannen» bei `features.includes('scan')` → `send('scan', {format: 'pdf'})`.
2. `on('file', …)`: `source === 'scan'` → wie ein Upload an die offene Lektion hängen.

**Rückfall ohne Anschluss:** Scannen geht über das Kürzel ⌥⌘S, danach erscheint die Vorschau mit Teilen-Menü (siehe 1.).

## 4. Tastatur-Kürzel

Die App fängt die Kürzel ab (⌘ halten zeigt die Übersicht) und schickt sie als Ereignis an die Web-App, wenn die Web-App darauf hört. Sonst nimmt sie den Rückfall.

| Kürzel | Ereignis (App → Web) | Rückfall ohne Anschluss |
|---|---|---|
| ⌘⇧B Classroom Screen an/aus | `screen-toggle` `{open}` | offen: `window.close()` im Screen; zu: `window.open('/?classroom=1')` |
| ⌥⌘→ / ⌥⌘← Phase | `phase-next` / `phase-prev` | Taste `ArrowRight`/`ArrowLeft` an den offenen Screen (csKey) |
| ⌘⇧T Timer | `timer-toggle` | Screen offen: Leertaste an den Screen; sonst Timer der Beamer-Ebene |
| ⌘F Suchen | `search` | erstes `input[type=search]` bzw. Platzhalter «…uch…» fokussieren |
| ⌘⇧D Bildschirm schwarz | – (immer nativ) | – |
| ⌘⇧K Kamera, ⌥⌘S Scannen, ⌘⇧A Ruhe-Ampel, ⌘⇧P Fernbedienung, ⌘O Import, ⌘P Drucken, ⌘R Neu laden, ⌘/ Übersicht | – (nativ) | – |

Web → App: `send('command', {id: 'black-toggle'})` löst jedes Kürzel auch aus der Web-App aus (`id` = Ereignisname bzw. `camera`, `scan`, `quiet-toggle`, `beamer-panel`, `import`, `print`, `reload`).

**Web-Anschluss (empfohlen, klein):**
- `on('phase-next')`, `on('phase-prev')`, `on('timer-toggle')` im Planer registrieren (das Screen-Fenster hat dort seinen `opener`) und die Funktionen des Screens direkt aufrufen. Das ist robuster als der Tastendruck-Rückfall und funktioniert auch, wenn gerade ein Eingabefeld im Screen den Fokus hat.
- `on('search')` → die eigene Suche öffnen.
- `on('screen-toggle')` → `startCS()` bzw. `closeCS()`, damit die heutige Lektion gewählt wird.

## 5. Teilen-Menü, Drucken, Dateien

| Richtung | Name | Nutzlast |
|---|---|---|
| Web → App | `share` | `{name, type, data: base64}` oder `{url}` oder `{text}`. Helfer: `klassentaktShell.share({name, blob})` |
| Web → App | `print` | `{}` = Seite drucken, die es schickt (Planer oder Screen); `{name, type, data}` = diese Datei. Helfer: `klassentaktShell.print({name, blob})` |
| Web → App | `pickFiles` | `{types?: ['pdf','image','ics','klassentakt','video','audio','any' \| '.ext'], multiple?: boolean}` |
| App → Web | `file` | `{source: 'import'\|'open'\|'drop', name, type, size, file: File}` |

Was die App tut, schon ohne Anschluss:
- **Exporte** über `<a download>`, `blob:` und `data:`, auch mit `target=_blank`, sowie Antworten mit `Content-Disposition: attachment` oder `text/calendar` lädt die App herunter. PDF und Bilder erscheinen als Vorschau (Teilen, Drucken), alles andere (ICS, JSON, .klassentakt, HTML) direkt im Teilen-Menü. **Damit gehen die heutigen Exporte schon ohne Web-Änderung.**
- **`window.print()`** wird auf AirPrint umgeleitet (bisher tat es im WKWebView nichts). ⌘P druckt den Planer.
- **«Öffnen in» Klassentakt** aus Dateien und AirDrop ist für PDF, Bilder, ICS und `.klassentakt` angemeldet. `.klassentakt` ist als eigener Dateityp `ch.klassentakt.paket` erklärt.
- **Drag & Drop:** Ablagen der Web-App (`drop`-Handler mit `dataTransfer.files`) bekommen Dateien direkt von WebKit, wie im Browser. Die App nimmt zusätzlich Drops auf ihre eigenen Flächen an (Knopf «Beamer», Statusleisten-Streifen) und gibt sie als `file` (`source: 'drop'`) weiter.

**Web-Anschluss:**
1. `on('file', …)` **einmal zentral** (im Planer) registrieren und nach `source` und Typ verteilen: Bild/PDF an die offene Lektion bzw. die Material-Ablage, `.klassentakt` an den Bibliotheks-Import, `.ics` an einen Kalender-Import (falls es den gibt, sonst Hinweis). Solange niemand auf `file` hört, öffnet die App die Vorschau mit Teilen-Menü. Beim Kaltstart über «Öffnen in» wartet die App bis zu 10 s, bis die Seite auf `file` hört.
2. Optional: Knopf «Aus Dateien» bei `features.includes('files')` → `send('pickFiles', {types: ['pdf','image']})`. Ohne `on('file')` zeigt ⌘O nur einen Hinweis.
3. Optional: eigene Knöpfe «Teilen»/«Drucken» für Wochenplan und Lektion → `klassentaktShell.share({name: 'Wochenplan KW 46.pdf', blob})`. Heute reicht schon der bestehende Download-Weg.
4. Ein ICS-Export existiert in `web/index.html` noch nicht (nur PDF/JSON/HTML). Wenn er kommt, genügt `<a download="… .ics">`.

## Was die Web-App mindestens tun sollte (Reihenfolge nach Nutzen)

1. `on('file')` zentral mit Verteilung (Scans, Kamera-Fotos, Import, Öffnen in). Das ist der grösste Gewinn, etwa ½ Tag.
2. Knöpfe «Scannen» und «Dokumentenkamera» bei `features`, etwa ¼ Tag.
3. `on('phase-next' | 'phase-prev' | 'timer-toggle' | 'search' | 'screen-toggle')`, etwa ¼ Tag.
4. Optional: `beamer`-Zustand im Screen-Menü, Knopf «Fernbedienung», `overlay`-Timer.

Testen ohne iPad: In der Browser-Konsole eine Attrappe setzen, zum Beispiel `window.klassentaktShell = {isShell:true, platform:'ios', features:['scan','camera','files'], send:(n,p)=>console.log(n,p), on:(n,f)=>(window['_kt_'+n]=f, ()=>{})}`. Ein Scan lässt sich dann mit `_kt_file({source:'scan', name:'Scan.pdf', type:'application/pdf', file: new File(['%PDF'], 'Scan.pdf')})` nachstellen. Nur erfundene Namen und Daten verwenden.
