# Brücke iPad-App ↔ Web-App, Paket A (Stand 04.11.2026, Fassung 2: Kamera als Werkzeug, keine native Beamer-Ebene)

Rolle «Apple-Apps» für die Rolle «Web-App». Die App-Seite ist auf dem Branch `claude/ipad-paket-a-cae7e1` gebaut (`ios/Klassentakt/Bridge.swift`). In `web/index.html` ist **nichts** geändert. Jede Funktion läuft auch ohne Web-Anschluss, mit dem Rückfall, der unten pro Funktion beschrieben ist. Die Anschlüsse machen das Ganze nur runder.

## Grundlagen

Die App setzt `window.klassentaktShell` nur auf `klassentakt.ch` und `*.klassentakt.ch`, und zwar vor dem ersten Script der Seite (Hauptframe). Im Screen-Fenster (`about:blank` + `document.write`) gibt es die Brücke nicht. Dort gilt wie bisher `ktShell()` → `window.opener.klassentaktShell`.

```js
klassentaktShell = {
  isShell: true, platform: 'ios', shellVersion: '1.0.0',
  features: ['beamer-extern','shortcuts','scan','camera','camera-capture','share','print','files','editing','display-state'],  // 'scan'/'camera' nur, wenn das Gerät es kann
  send(name, payload),        // Web → App, payload = einfaches JSON-Objekt
  on(name, fn) → off(),       // App → Web, fn(payload)
  share({ name, type, blob }) → Promise,  // Helfer: liest blob als Base64 und schickt 'share'
  print({ name, type, blob }) → Promise,  // Helfer: dito für 'print'
}
```

- **Anmelden = zuhören.** `on(name, fn)` meldet der App: «diese Seite kann `name`». Ohne Anmeldung nimmt die App ihren Rückfall. `off()` (der Rückgabewert) meldet wieder ab, ein Neuladen ebenfalls.
- Jedes Ereignis kommt zusätzlich als `window` CustomEvent `klassentakt-shell` mit `detail: {name, payload}`, zum Mitlesen ohne Anmeldung.
- Das bisherige Ereignis `klassentakt-beamer` (`{open, extern}`) bleibt unverändert.
- Erkennen: `sh.platform === 'ios' && sh.features.includes('camera')` usw. `camera` fehlt bei einem iPad ohne Rückkamera, `scan` dort, wo VisionKit nicht scannen kann. Die Web-App zeigt die Werkzeuge nur, wenn das Merkmal da ist. Die Mac-App hat andere `features`, `send`/`on` gibt es dort nicht.
- Nachrichten aus iframes (YouTube usw.) nimmt die App nicht an.
- **Im Screen-Fenster** geht alles über `ktShell()` (= `opener.klassentaktShell`): `ktShell().send('open-camera')` und `ktShell().on('camera', fn)` funktionieren von dort aus.
- `ref` (frei wählbarer Text, höchstens 200 Zeichen) gibt die Web-App bei `open-camera` und `open-scanner` mit. Die App schickt ihn im `file`-Ereignis unverändert zurück. So weiss die Web-App, an welche Lektion oder Ablage das Ergebnis gehört.
- Das iPad hat kein `sh.beamer` (das ist die Mac-API). Das ist Absicht, damit das bestehende Menü «Auf anderen Bildschirm» nicht erscheint.

## Was sich gegenüber Fassung 1 ändert

Florian hat entschieden, dass die Werkzeuge im Classroom Screen der Web-App bleiben. Die App baut keine eigenen.

- **Weg:**
  - die native Beamer-Ebene mit Timer, Ruhe-Ampel und «schwarz»
  - der Knopf «Beamer» mit der Fernbedienung
  - die Auswahl beim Verbinden
  - die Nachrichten `overlay` und `beamerPanel`
  - das Merkmal `beamer-layer`
  - die Kürzel ⌘⇧D und ⌘⇧P
- **Neu:**
  - Die Dokumentenkamera ist ein **Werkzeug im Werkzeugkoffer** der Web-App und startet mit `send('open-camera')`.
  - Der Scanner ist ein **Anhang** in der Lektion bzw. Ablage und startet mit `send('open-scanner')`.
  - Die Kürzel ⌘⇧T und ⌘⇧A lösen die Werkzeuge der Web-App aus, über das Ereignis `tool`.
- **Bleibt:**
  - Der Beamer zeigt über die eigene Szene den Classroom Screen der Web-App.
  - Teilen, Drucken und Dateien bleiben unverändert, ebenso die übrigen Kürzel.

## 1. Dokumentenkamera (Werkzeug im Werkzeugkoffer)

| Richtung | Name | Nutzlast |
|---|---|---|
| Web → App | `open-camera` | `{ref?: string, mode?: 'live'}`: `mode:'live'` ist der Visualizer, nur Live-Bild ohne «Foto übernehmen» |
| Web → App | `open-camera` mit `mode:'foto'` | `{mode:'foto', allowScan?: boolean, scanFormat?: 'pdf'\|'image', ref}`: Anhang. Die Kamera startet als Foto, «Auslösen» schickt `file {source:'camera', ref}` und schliesst. Mit `allowScan` gibt es den Umschalter «Foto \| Scannen»: «Scannen» öffnet den Scanner von iOS, danach kommt `file {source:'scan', ref}`. «Abbrechen» im Scanner führt zurück zum Foto. Nichts am Beamer. Merkmal `camera-capture`. |
| Web → App | `close-camera` | `{}` |
| App → Web | `camera` | `{open: boolean}`, bei jedem Öffnen und Schliessen, zuerst gleich nach `on('camera')` |
| App → Web | `file` | `{source: 'camera', ref?, name: 'Dokumentenkamera 2026-11-04 09.41.jpg', type: 'image/jpeg', size, file: File}` |

Was die App tut:
- Sie öffnet die Kamera nativ im Vollbild auf dem iPad, mit Vorschau und Knöpfen.
- Bedienung: Zoom mit zwei Fingern, Einfrieren, Drehen, Licht, «Foto übernehmen», «Schliessen».
- Ist ein Beamer verbunden, zeigt er das Live-Bild statt des Classroom Screens. Nach dem Schliessen zeigt er wieder den Screen.
- Ohne Beamer ist es eine Lupe bzw. ein Fotoapparat auf dem iPad.

**Web-Anschluss (Rolle Web-App):**
1. In `TOOLS` einen Eintrag ergänzen, etwa so:
   ```js
   { k: "doccam", n: "Dokumentenkamera", ic: …, on: () => KTCAM.open, a: () => "@doccam", hide: () => !ktHas("camera") }
   ```
   Dabei gilt:
   - `ktHas = f => { const sh = ktShell(); return !!(sh && sh.platform === 'ios' && (sh.features || []).includes(f)); }`
   - In `tlRun` wird `"@doccam"` zu `KTCAM.open ? ktShell().send('close-camera') : ktShell().send('open-camera', {ref: …})`.
2. Im Screen einmal `ktShell().on('camera', st => { KTCAM.open = st.open; renderCS(); })` aufrufen, damit die Kachel «an» zeigt.
3. `on('file')` mit `source === 'camera'`: Das Foto kommt an die aktuelle Lektion bzw. den Ablauf (siehe 5.).

**Rückfall ohne Anschluss:**
- Die Kamera öffnet sich mit ⌘⇧K.
- «Foto übernehmen» öffnet eine Vorschau mit Teilen-Menü und Drucken. Ein Hinweis sagt, dass diese Klassentakt-Version das Foto noch nicht direkt übernimmt.

## 2. Beamer (eigene Szene, zeigt den Classroom Screen)

| Richtung | Name | Nutzlast |
|---|---|---|
| App → Web | `beamer` | `{open, extern, camera, mode: 'erweitern', steuern}` (`open` = Screen-Fenster offen, `extern` = Beamer verbunden, `steuern` = Screen gerade gross auf dem iPad) |
| App → Web | `klassentakt-beamer` (CustomEvent, wie bisher) | `{open, extern}` |

Was die App tut:
- Auf dem externen Bildschirm (HDMI oder AirPlay «erweitern») zeigt sie den Classroom Screen der Web-App im Vollbild, bei offener Kamera deren Bild. Das iPad bleibt frei für Planer und Notizen.
- Solange kein Screen offen ist, zeigt der Beamer eine ruhige Platzhalterseite mit dem Klassentakt-Logo und «Classroom Screen auf dem iPad öffnen». Er spiegelt **nie** den Planer.
- Beim Verbinden (Vorschlag, statt der Auswahl von Fassung 1): Ist der Screen schon offen, erscheint auf dem iPad nur kurz «Beamer verbunden, zeigt den Classroom Screen». Sonst erscheint ein Hinweis, der nicht blockiert und nach 8 s verschwindet, mit dem Knopf «Classroom Screen öffnen». Es gibt keine Auswahl und keinen Dialog.

**Immer erweitert (Florians Entscheid vom 6.11.):** Den Schalter «Erweitern | Spiegeln» gibt es nicht mehr. Der Planer erscheint nie vorne. `mode` bleibt im Ereignis `beamer` erhalten und ist immer `'erweitern'`.

- **Erweitert:**
  - Der Screen läuft am Beamer. Auf dem iPad zeigt ein verschiebbares Fenster (Bild im Bild) live, was am Beamer läuft.
  - **Antippen = Steuern:** Derselbe Screen kommt gross aufs iPad, in Beamer-Grösse und verkleinert, damit am Beamer nichts umbricht. Er lässt sich dort bedienen: zeichnen, Werkzeuge öffnen und schliessen usw. Der Beamer zeigt sein Live-Bild.
  - Der Knopf «Zum Planer» bringt den Screen zurück an den Beamer, er läuft weiter.
- Das Bild im Bild ist frei in der Grösse (zwei Finger oder Griff). «–» blendet es aus, zurück kommt es über den Griff am rechten Rand oder mit ⌘⇧B.
- Es gibt immer **nur einen Screen**, also ein WebView mit einem Zustand. Die App kopiert nur das Bild. Die Web-App muss dafür nichts tun, gekoppelte Screens braucht es auf dem iPad nicht.

**Web-Anschluss:** keiner nötig. Optional `on('beamer')`, um im Screen «auf dem Beamer» bzw. den Modus anzuzeigen.

**Bearbeiten-Popup (`editing`):** Meldet die App das Merkmal `editing`, schickt die Web-App `send('editing', {open: true})`, bevor sie das Popup «Schritt bearbeiten» öffnet, und `{open: false}` nach dem Schliessen.
- Solange das Popup offen ist, zeigt der Beamer das letzte Bild weiter, und das Popup bleibt auf dem iPad. Das gilt am Beamer und beim Steuern.
- Spätestens nach 15 Minuten oder beim Schliessen des Screens zeigt der Beamer wieder live, falls das `{open:false}` verloren geht.

**Sichtbarkeit nach aussen (`display-state`):** Für Inhalte, die die Kinder nicht sehen dürfen (Schritte «nur für mich»).
- Ereignis `on('display', d)` mit `d = {shown: bool, how: 'beamer'|'capture'|'none'}`. Es gilt **pro WebView** (Planer und Screen getrennt), kommt nach `on('display')`, bei jeder Änderung und als Antwort auf `send('display-get')`.
- `shown: true`, wenn:
  - `capture`: iPadOS nimmt auf oder spiegelt (Bildschirmaufnahme, AirPlay-Synchronisierung).
  - `beamer`: Der Screen beim Erweitern, solange ein Beamer verbunden ist. Das gilt auch beim Steuern, weil der Beamer dann ein Live-Bild zeigt.
- `shown: false` (`none`): kein Beamer, oder der Planer beim Erweitern. Das Bild im Bild bleibt auf dem iPad.
- Reihenfolge: Beim Einstecken sendet die App zuerst `display` und zeigt das Bild erst 150 ms später nach aussen.
- Ohne das Merkmal (z. B. Safari) muss die Web-App solche Inhalte gesperrt lassen.

## 3. Scanner (Anhang in Lektion und Ablage)

| Richtung | Name | Nutzlast |
|---|---|---|
| Web → App | `open-scanner` | `{format?: 'pdf'\|'image', ref?: string}`. Ohne Format fragt die App nach dem Scannen. (`scan` bleibt als alter Name gültig.) |
| App → Web | `file` | `{source: 'scan', ref?, name: 'Scan 2026-11-04 09.41.pdf', type: 'application/pdf'\|'image/jpeg', size, file: File}`. Bei `image` und mehreren Seiten kommt ein Ereignis pro Seite, `… (2).jpg` |

Was die App tut:
- Sie öffnet den VisionKit-Scanner: zuschneiden, entzerren, mehrere Seiten.
- Die Seiten werden auf höchstens 2200 px verkleinert. Das PDF ist A4 hoch oder quer, die Bilder sind JPEG mit 75 %.

**Web-Anschluss:**
1. Dort, wo es heute «Datei hochladen» bzw. «Anhang» gibt (Lektion, Material), bei `ktHas('scan')` den Eintrag «Scannen» ergänzen. Er ruft `ktShell().send('open-scanner', {format: 'pdf', ref: lektionId})` auf. Im Werkzeugkoffer des Screens braucht es den Scanner nicht.
2. `on('file')` mit `source === 'scan'`: Der Scan wird über `ref` an die richtige Lektion gehängt, wie ein Upload.

**Rückfall ohne Anschluss:** Scannen geht mit ⌥⌘S. Danach öffnet sich die Vorschau mit Teilen-Menü (siehe 1.).

## 4. Tastatur-Kürzel

Die App fängt die Kürzel ab (⌘ halten zeigt die Übersicht). Hört die Web-App auf das Ereignis, bekommt sie es als Ereignis. Sonst nimmt die App den Rückfall.

| Kürzel | Ereignis (App → Web) | Rückfall ohne Anschluss |
|---|---|---|
| ⌘⇧B Classroom Screen an/aus | `screen-toggle` `{open}` | offen: `window.close()` im Screen; zu: `window.open('/?classroom=1')` |
| ⌥⌘→ / ⌥⌘← Phase | `phase-next` / `phase-prev` | Taste `ArrowRight`/`ArrowLeft` an den offenen Screen (`csKey`) |
| ⌘⇧T Timer | `tool` `{k: 'timer'}` | Screen offen: Leertaste an den Screen (`tToggle`); sonst Hinweis «Zuerst den Classroom Screen öffnen (⌘⇧B)» |
| ⌘⇧A Ruhe | `tool` `{k: 'ruhe'}` | Hinweis «Ruhe im Werkzeugkoffer des Classroom Screens» |
| ⌘F Suchen | `search` | erstes `input[type=search]` bzw. Platzhalter «…uch…» fokussieren |
| ⌘⇧K Dokumentenkamera, ⌥⌘S Scannen, ⌘O Import, ⌘P Drucken, ⌘R Neu laden, ⌘/ Übersicht | – (nativ) | – |

- `tool` ist bewusst allgemein gehalten. `k` ist der Schlüssel aus `TOOLS`, also `timer`, `ruhe` und später vielleicht weitere. Die Web-App ruft dafür `tlRun(TOOLS.find(t => t.k === k).a())` auf, die Werkzeuge bleiben damit ganz in der Web-App.
- Web → App: `send('command', {id})` löst die nativen Kürzel auch aus der Web-App aus, mit `id` aus `camera`, `scan`, `import`, `print`, `reload`.

**Web-Anschluss (empfohlen, klein):**
- `on('tool')`, `on('phase-next')`, `on('phase-prev')` im Screen-Fenster registrieren, über `ktShell()`, beim Schliessen mit `off()` abmelden.
- `on('search')` und `on('screen-toggle')` im Planer: Die eigene Suche öffnen, bzw. `startCS()` und `closeCS()` aufrufen.

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
- **Drag & Drop:** Ablagen der Web-App (`drop`-Handler mit `dataTransfer.files`) bekommen Dateien direkt von WebKit, wie im Browser. Die App nimmt zusätzlich Drops auf ihre eigene Fläche an (Statusleisten-Streifen oben) und gibt sie als `file` (`source: 'drop'`) weiter.

**Web-Anschluss:**
1. `on('file', …)` **einmal zentral** (im Planer) registrieren und nach `source` und Typ verteilen: Bild/PDF an die offene Lektion bzw. die Material-Ablage, `.klassentakt` an den Bibliotheks-Import, `.ics` an einen Kalender-Import (falls es den gibt, sonst Hinweis). Solange niemand auf `file` hört, öffnet die App die Vorschau mit Teilen-Menü. Beim Kaltstart über «Öffnen in» wartet die App bis zu 10 s, bis die Seite auf `file` hört.
2. Optional: Knopf «Aus Dateien» bei `features.includes('files')` → `send('pickFiles', {types: ['pdf','image']})`. Ohne `on('file')` zeigt ⌘O nur einen Hinweis.
3. Optional: eigene Knöpfe «Teilen»/«Drucken» für Wochenplan und Lektion → `klassentaktShell.share({name: 'Wochenplan KW 46.pdf', blob})`. Heute reicht schon der bestehende Download-Weg.
4. Ein ICS-Export existiert in `web/index.html` noch nicht (nur PDF/JSON/HTML). Wenn er kommt, genügt `<a download="… .ics">`.

## Was die Web-App mindestens tun sollte (Reihenfolge nach Nutzen)

1. Das Werkzeug «Dokumentenkamera» in `TOOLS` (`open-camera`, `close-camera`, `on('camera')`), etwa ¼ Tag.
2. `on('file')` zentral mit Verteilung nach `source` und `ref` (Kamera-Fotos, Scans, Import, Öffnen in), etwa ½ Tag.
3. «Scannen» beim Anhang bzw. Upload (`open-scanner` mit `ref`), etwa ¼ Tag.
4. `on('tool' | 'phase-next' | 'phase-prev' | 'search' | 'screen-toggle')`, etwa ¼ Tag.

Testen ohne iPad: In der Browser-Konsole eine Attrappe setzen, zum Beispiel:

```js
window.klassentaktShell = {isShell:true, platform:'ios', features:['scan','camera','files'],
  send:(n,p)=>console.log(n,p), on:(n,f)=>(window['_kt_'+n]=f, ()=>{})}
```

Dann `_kt_camera({open:true})` für den Zustand aufrufen, und `_kt_file({source:'camera', ref:'L1', name:'Dokumentenkamera.jpg', type:'image/jpeg', file: new File([''], 'Dokumentenkamera.jpg')})` für ein übernommenes Foto. Dabei nur erfundene Namen und Daten verwenden.
