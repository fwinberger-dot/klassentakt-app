# App Store: Launch iPad und Mac – Bestandsaufnahme (Stand 04.11.2026)

Rolle «Apple-Apps». Quellen: `docs/AppStore-Einreichung.md` (Web-Repo), dieses Repo (`ios/`, `src/`, `build/`, Branch `apple-login`), Notizen von Server und Web-App, App Review Guidelines. Code ist dafür nicht geändert worden.

**Kurz:**
- **iPad** zuerst in den App Store, und zwar so schnell wie möglich nach dem Umzug.
- **Mac** bleibt vorerst bei Developer ID über `/download/`, der Mac App Store kommt als zweiter Schritt.
- Grösstes Risiko ist 4.2 «nur Web-Hülle». Zweitgrösstes: Der Apple-Login der App passt noch nicht zum Server.

---

## 1. Vertriebsweg

### iPad: App Store (einziger Weg)
- Bundle-ID `ch.klassentakt.app`, nur iPad (`TARGETED_DEVICE_FAMILY 2`), ab iPadOS 16. Der Build läuft über den Workflow `ios.yml` → TestFlight, das Profil «Klassentakt App Store» ist vorhanden.
- **iPad-App auf Macs mit Apple Silicon** («Designed for iPad») bei der ersten Version **ausschalten**. Grund: Die Beamer-Szene und die Kamera sind dort nicht getestet, und das würde sich mit der Mac-App überschneiden.

### Mac: weiter Developer ID, Mac App Store erst in Phase 2 (Empfehlung)
| | Developer ID (heute) | Mac App Store (MAS) |
|---|---|---|
| Stand | fertig: 0.4.1 signiert und notarisiert, Download über `/download/mac`, Selbst-Update | nichts vorhanden |
| Aufwand | – | Electron-`mas`-Build mit App Sandbox, eigene Entitlements (Netzwerk, Kamera, Mikrofon, Benutzer-Dateien), Selbst-Update ausbauen (in MAS verboten), neue Zertifikate: «Apple Distribution» bzw. «3rd Party Mac Developer Application» und «Mac Installer Distribution», Mac-Provisioning-Profil, zweiter Workflow-Zweig. Etwa 2–3 Tage plus Prüfung. |
| Prüf-Risiko | keines (nur Notarisierung, die automatisch läuft) | **hoch bei 4.2**: Eine Electron-Hülle mit Website-Inhalt ist der klassische Ablehnungsgrund, und die Mac-Hülle hat weniger Natives als das iPad (Beamer-Fenster, Menüs, Update) |
| Nutzen | Lehrpersonen laden die App über den Knopf in der Web-App | Fund im Store, automatische Updates über Apple, bei gleicher Bundle-ID «Universal Purchase» mit dem iPad (ein Eintrag) |

**Begründung:** Der Mac-Weg funktioniert seit heute. Ein MAS-Build würde Arbeit in der Woche des Umzugs binden und das Ablehnungsrisiko auf zwei Apps verteilen. Besser: iPad zuerst durch die Prüfung bringen. Das Feedback der Prüfung zu 4.2 nehmen wir mit. Danach entscheiden wir, ob sich MAS lohnt, frühestens Ende November. Falls ja, kommt der MAS-Build unter derselben Bundle-ID `ch.klassentakt.app` als macOS-Plattform in denselben App-Store-Connect-Eintrag.

---

## 2. Ablehnungsrisiken

Status: ✅ vorhanden · 🟡 teilweise · ❌ fehlt

| Richtlinie | iPad | Mac (nur wenn MAS) | Was fehlt / Massnahme |
|---|---|---|---|
| **4.2 Minimalfunktion / «nur Web-Hülle»** | 🟡 | 🟡 (eher ❌) | **Nativ auf dem iPad:** eigene Beamer-Szene auf dem externen Bildschirm (`UIWindowSceneSessionRoleExternalDisplayNonInteractive`), Classroom Screen im Vollbild auf dem Beamer, während das iPad weiter steuert; Kamera (Dokumentenkamera) und Mikrofon (Ruhe-Timer) mit Berechtigung; Google-Login über `ASWebAuthenticationSession`; Deep Link `klassentakt://`; eigene Offline-Seite; Statusleiste passt sich der Kopfzeile an; nativer Apple-Login vorbereitet. **Nativ auf dem Mac:** Beamer-Fenster auf dem zweiten Bildschirm, App-Menüs, Update-Fenster. **Fehlt:** Offline-Betrieb (ohne Netz nur die Offline-Seite), Teilen-Menü und Dateien-App (Export als PDF/ICS), Pencil oder Tastatur-Kürzel, Hinweis auf den Beamer beim Verbinden. **Massnahme:** In den Notizen für die Prüfung die Beamer-Funktion mit externem Bildschirm (oder AirPlay) ausdrücklich beschreiben und ein kurzes Video verlinken. Wenn möglich vor der Einreichung 1–2 kleine native Funktionen einbauen, Vorschlag: Teilen-Menü für Export und Tastatur-Kürzel. |
| **4.8 Mit Apple anmelden** (Pflicht, weil Google, Microsoft und Jobnavigator angeboten werden) | 🟡 | 🟡 | **Server:** fertig, gegen eine Attrappe getestet (Web, `/auth/apple/native`, Widerruf beim Löschen, notify). **App:** Branch `apple-login` (9f8a982) ist vorbereitet, **passt aber nicht zum API-Vertrag**: Die App schickt `x-www-form-urlencoded` mit `fullName`, `docs/API.md` will JSON mit `X-Klassentakt: 1` und `name: {givenName, familyName}`, die Antwort enthält `redeem` für den WebView. → Vor dem Merge anpassen (Apple-Apps). **Mac:** über den Web-Flow im Browser und den `klassentakt://`-Rücksprung (es gibt keinen nativen Dialog in Electron). **Florian:** Portal-Klicks laut Server-Bericht (App-ID-Capability, Services-ID, Key, notify, E-Mail-Relay), Key über `/admin/setup`. Echter Test gegen Apple: erst danach auf TestFlight. |
| **5.1.1(v) Konto löschen in der App** | 🟡 | 🟡 | Server `deleteaccount` ✅ (sperren, 30 Tage, Apple-Token widerrufen). Web-App ✅ in v141 («Profil → Mein Konto → Konto löschen»). Die App zeigt die Web-App, also gilt das automatisch, **sobald v141 und der neue Server live sind** (nach dem Umzug). Auf dem alten Server gibt es nur einen Hinweis per Mail, und das reicht Apple nicht. |
| **Datenschutz-Manifest `PrivacyInfo.xcprivacy`** | ❌ | ❌ | Fehlt im iPad-Projekt. Der eigene Swift-Code nutzt keine «Required Reason»-APIs (kein `UserDefaults`, keine Datei-Zeitstempel), WKWebView ist Sache von Apple. Trotzdem eine Manifest-Datei anlegen: `NSPrivacyTracking false`, keine Tracking-Domains, `NSPrivacyCollectedDataTypes` passend zu den Angaben in App Store Connect. Mac/MAS: prüfen, ob Electron 44 ein Manifest mitbringt, sonst im `mas`-Build ergänzen. (Apple-Apps, 1 h) |
| **Datenschutz-Angaben (App Privacy)** | 🟡 | 🟡 | Entwurf im Projekt-Doc «Klassentakt_AppStore_Eintrag». Ergänzen: E-Mail und Name (Konto, auch über Apple-Login), «Andere Benutzerinhalte» (Planungen, Klassenlisten mit Vornamen), alles «mit Identität verknüpft», **kein Tracking**, keine Werbung, keine Analytics. Datenschutz-URL `https://klassentakt.ch/datenschutz` muss live sein (Adresse im Impressum fehlt noch). |
| **Altersfreigabe** | 🟡 | 🟡 | Fragebogen ausfüllen: keine kritischen Inhalte → niedrigste Stufe. **Nicht** in die Kategorie «Kids» (Zielgruppe sind Lehrpersonen). Frage «Benutzergenerierte Inhalte / Austausch zwischen Nutzern»: Lehrpersonen teilen Klassen und die Bibliothek nur mit eingeladenen Personen, es gibt nichts Öffentliches. Richtig beantworten; falls Apple 1.2 anwendet, braucht es Melden/Blockieren (heute ❌). |
| **Kinderdaten / Schulkontext** (5.1.1, 5.1.4) | 🟡 | 🟡 | Kinder benutzen die App nicht, es gibt kein Kinder-Konto. Lehrpersonen erfassen Vornamen von Schülerinnen und Schülern. Das sind Daten über Dritte; sie liegen in der Schweiz (Infomaniak), kein Tracking. In den Prüf-Notizen und der Datenschutzerklärung klar sagen: «Für Lehrpersonen. Schülerdaten nur Vornamen, Hosting Schweiz, keine Weitergabe.» Das Demo-Konto enthält nur erfundene Namen. |
| **Export Compliance** | ✅ | ❌ | iPad: `ITSAppUsesNonExemptEncryption = false` steht in `project.yml` (nur HTTPS, Ausnahme). Mac/MAS: denselben Schlüssel in `extendInfo` setzen. |
| **Demo-Konto für die Prüfung** (2.1) | ❌ | ❌ | Anleitung steht in `AppStore-Einreichung.md` (apple-review@klassentakt.ch, Klasse «Demo 5a»). Florian legt es **nach dem Umzug** auf klassentakt.ch an und trägt es nur in App Store Connect ein. |
| **2.1 Vollständigkeit / Stabilität** | 🟡 | – | TestFlight-Builds laufen. Florians Test am echten Beamer ist offen. Die Prüfung läuft gegen den Live-Server, also erst nach dem Umzug einreichen. |
| **2.5.2 / 2.4.5 Code nachladen, Selbst-Update** | ✅ | ❌ | iPad: lädt nur Webinhalte, das ist erlaubt. Mac/MAS: Selbst-Update `updater.js` muss im `mas`-Build ausgeschaltet sein. |
| **5.1.1(i) Datenschutzerklärung in der App** | 🟡 | 🟡 | Link in der Web-App vorhanden, sobald `/datenschutz` vom neuen Server kommt. |
| **3.1 Zahlungen** | ✅ | ✅ | Gratis, keine Käufe. |

---

## 3. App Store Connect

| | iPad | Mac (Phase 2) |
|---|---|---|
| App-Eintrag | «Klassentakt», Plattform iOS, Hauptsprache Deutsch, SKU z.B. `klassentakt-ipad` | Plattform macOS im **gleichen** Eintrag hinzufügen (Universal Purchase) |
| Bundle-ID | `ch.klassentakt.app` (Capability «Sign in with Apple») | `ch.klassentakt.app` (gleiche, dann Universal Purchase) |
| Screenshots | iPad 13" 2752 × 2064 (oder 2064 × 2752), 1–10 Stück. ✅ 6 Stück in `shots/appstore/`, mit erfundenen Namen. Apple-Login-Knopf auf der Anmeldeseite noch nachführen. | 16:10, z.B. 2880 × 1800 oder 1440 × 900, 1–10 Stück. ❌ |
| Optional | App-Vorschau-Video (Beamer zeigen, hilft bei 4.2) | – |
| Texte (DE) | Name (30 Zeichen), Untertitel (30), Werbetext (170), Beschreibung (4000), Stichwörter (100), «Was ist neu». ✅ im Projekt-Doc «Klassentakt_AppStore_Eintrag», Apple-Login ergänzen | gleich, Mac-spezifisch ergänzen |
| URLs | Support `https://klassentakt.ch/` (oder eine Kontaktseite), Datenschutz `https://klassentakt.ch/datenschutz`, Marketing optional | gleich |
| Kategorie | Bildung (primär), Produktivität (sekundär) | gleich (`public.app-category.education` steht schon) |
| Altersfreigabe, App Privacy, Export | siehe oben | siehe oben |
| Prüfung | Kontakt (Name, Tel., E-Mail), Demo-Konto, Notizen inkl. Beamer und Konto löschen | gleich |
| Preis / Verfügbarkeit | gratis, nur Schweiz (Entscheid 03.11.) | gleich |
| Copyright | «© 2026 Florian Winberger» | gleich |

---

## 4. Zeitplan

| Wann | Apple-Apps (ich) | Florian |
|---|---|---|
| **Do 05.11.** | Branch `apple-login` an `docs/API.md` anpassen (JSON, `X-Klassentakt`, `name`, `redeem`), `PrivacyInfo.xcprivacy`, Notizen für die Prüfung (Entwurf), Vorschlag für die Datenschutz-Angaben. Kein Merge. | Apple-Portal-Klicks für «Sign in with Apple» (Liste im Server-Bericht), Key über `/admin/setup` auf staging |
| **Fr 06.11.** | Apple-Login gegen staging (TestFlight-Build aus dem Branch, wenn freigegeben). Optional native Kleinigkeit gegen 4.2 (Teilen-Menü / Kürzel). | iPad am Beamer testen (TestFlight). Entscheide unten. |
| **Sa/So 07./08.11.** | Umzug, nur Bereitschaft, keine Builds | Umzug. Danach Demo-Konto auf klassentakt.ch, Key über `/admin/setup` live |
| **Mo 09.11.** | `apple-login` mergen (mit Freigabe), Build 1.0.0 (2) → TestFlight, letzter Test gegen live: Login (E-Mail, Google, Apple), Konto löschen mit einem Testkonto, Beamer | App Store Connect: Eintrag ausfüllen (Texte, Screenshots, Privacy, Alter, Demo-Konto, Notizen), Build auswählen |
| **Di 10.11.** | Bereitschaft für Rückfragen der Prüfung | **Zur Prüfung einreichen** (iPad). Prüfung dauert meist 1–3 Tage |
| **ab ~13.11.** | Je nach Prüfung: Nachbesserung. Danach MAS-Entscheid vorbereiten | Freigabe «manuell veröffentlichen» |

---

## Für Florian: gesammelte Liste

**Entscheiden (bitte als Auswahl beantworten):**
1. Mac-Vertrieb: **A** Developer ID über `/download/` behalten, MAS frühestens nach dem iPad (Empfehlung) · **B** MAS jetzt parallel bauen
2. iPad-App auf Macs mit Apple Silicon: **A** ausschalten (Empfehlung) · **B** erlauben
3. Gegen 4.2 vor der ersten Einreichung: **A** 1–2 kleine native Funktionen (Teilen-Menü für Export, Tastatur-Kürzel), etwa ein Tag · **B** ohne, nur gute Prüf-Notizen und Video, nachbessern bei Ablehnung
4. Support-URL: **A** `https://klassentakt.ch/` · **B** eigene Seite `/hilfe` (Web-App/Server)
5. Veröffentlichung nach Freigabe: **A** manuell (Empfehlung) · **B** automatisch

**Klicken / tun:**
1. Apple-Portal «Sign in with Apple»: Schritte 1–6 im Server-Bericht, danach Key über `/admin/setup` (staging, am Umzugstag live).
2. Impressum: Adresse ergänzen (für die Datenschutz-URL nötig).
3. Nach dem Umzug: Demo-Konto `apple-review@klassentakt.ch` nach Anleitung, nur erfundene Namen, Zugang nur in App Store Connect eintragen.
4. iPad am echten Beamer testen (TestFlight) und Fehler melden.
5. App Store Connect: App-Eintrag anlegen (falls nicht vorhanden), Texte aus dem Projekt-Doc, 6 Screenshots, App Privacy, Altersfreigabe, Kontakt für die Prüfung; Build auswählen; einreichen.
6. **Sicherheit:** Die Schlüssel in `~/Downloads/klassentakt-signatur/` (.p12, .p8, Passwort-Datei) in den Schlüsselbund oder Passwortmanager verschieben und den Ordner löschen.
