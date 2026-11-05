# Mac App Store – Plan (Stand 05.11.2026)

Entscheid Florian (05.11.): Die Mac-App kommt in den Mac App Store. Die Download-Version 0.4.1 (Developer ID, Selbst-Update) bleibt, bis die Store-Version live ist. Eingereicht wird nur mit Florians Freigabe.

## Empfehlung in einem Satz
Die bestehende Electron-App bekommt ein **zweites Build-Ziel `mas`** mit App Sandbox und ohne Selbst-Update. Sie läuft unter **derselben Bundle-ID `ch.klassentakt.app` wie das iPad** (Universal Purchase, ein Eintrag in App Store Connect) und geht per Workflow auf TestFlight für den Mac. Etwa **3 Arbeitstage** bis zur TestFlight-Version, dazu die Prüfung durch Apple.

---

## 1. Was für den Mac App Store fehlt

| Bereich | Heute (Developer ID) | Für den Mac App Store | Aufwand |
|---|---|---|---|
| **App Sandbox** | keine | `build/entitlements.mas.plist`: `app-sandbox`, `network.client`, `device.camera`, `device.audio-input`, `files.user-selected.read-write` (Datei-Upload und Speichern-Dialog bei Downloads), `print`, `application-groups` = `Z28KL39TYK.ch.klassentakt.app` (braucht Electron), `com.apple.application-identifier` und `com.apple.developer.team-identifier` (braucht TestFlight). `build/entitlements.mas.inherit.plist` für die Helfer-Prozesse: `app-sandbox` + `inherit`. Ohne JIT- oder Hardened-Runtime-Ausnahmen. | 0,5 T |
| **Selbst-Update** | `updater.js`, Menü «Nach Updates suchen …», Tauschskript | Im MAS-Build ganz aus: Electron setzt dort `process.mas`. Kein Update-Check, kein Menüpunkt, `updater.js`, `update.html` und `update-preload.js` kommen gar nicht ins Paket (`mas.files`), und `features` meldet kein `update`. Eine Codebasis, zwei Ziele. | 0,25 T |
| **Build-Ziel und Workflow** | `mac.yml` → DMG/zip, notarisiert | Neuer Job in `mac.yml` (oder eigener `mas.yml`): `electron-builder --mac mas --universal` → `.pkg`, signiert mit «Apple Distribution» (App) und «Mac Installer Distribution» (pkg), Profil eingebettet, `buildVersion` = Laufnummer → Upload zu App Store Connect mit dem vorhandenen API-Key (`xcrun altool --upload-app -t macos`) → TestFlight. Version: **1.0.0** für den Store (Download bleibt 0.4.x). | 1 T (Electron-MAS braucht erfahrungsgemäss 2–3 Runden, bis Apples Upload-Prüfung durchgeht) |
| **Export Compliance** | – | `ITSAppUsesNonExemptEncryption = false` in `extendInfo` (nur HTTPS) | im obigen enthalten |
| **Datenschutz-Manifest** | – | Prüfen, ob das Electron-44-MAS-Framework ein `PrivacyInfo.xcprivacy` mitbringt (Chromium nutzt «Required Reason»-APIs). Sonst ein eigenes Manifest im App-Bundle wie beim iPad, mit Gründen für Datei-Zeitstempel, Systemlaufzeit, Speicherplatz und UserDefaults. | 0,25 T |
| **Mit Apple anmelden (4.8)** | Web-Flow im App-Fenster (`appleid.apple.com` steht in `LOGIN_HOSTS`, im Branch `apple-login`) | Bleibt der Web-Flow über die Services-ID `ch.klassentakt.web`. Electron hat keinen nativen Apple-Dialog, das ist für 4.8 erlaubt. Kein zusätzliches Entitlement nötig. Muss vor dem MAS-Build in `main` sein. | – |
| **Konto löschen (5.1.1(v))** | über die Web-App | wie beim iPad: «Profil → Mein Konto → Konto löschen», sobald v141 und der neue Server live sind | – |
| **Datenschutz-Angaben, Altersfreigabe, Preis, Verfügbarkeit** | – | Gelten **pro App-Eintrag**. Mit Universal Purchase übernimmt der Mac alles vom iPad: kein Tracking, E-Mail, Name und Benutzerinhalte; niedrigste Altersstufe; gratis; zuerst nur Schweiz. | – |
| **Kategorie** | `public.app-category.education` | gleich: Bildung, sekundär Produktivität | – |
| **Screenshots 2880 × 1800** | keine | 3–6 Stück mit erfundenen Daten: Planung, Wochenplan, Screen auf dem zweiten Bildschirm, Bibliothek. Skript `scripts/screenshots.js`: Electron mit 1440 × 900 bei Faktor 2 und `capturePage`, gegen staging mit dem Demo-Konto bzw. dem Sandbox-Stand der Web-App. | 0,5 T |
| **Testen in der Sandbox** | – | über TestFlight auf Florians Mac: Login (E-Mail, Google über den Browser, Apple), Kamera, Mikrofon, Beamer auf dem zweiten Bildschirm, Datei hochladen und herunterladen, Drucken, `klassentakt://`-Rücksprung | 0,5 T |
| **4.2 (nur Web-Hülle)** | Natives am Mac: Beamer-Fenster auf dem gewählten Bildschirm, Menüs mit Kürzeln, Kamera und Mikrofon | Prüf-Notizen wie beim iPad, Beamer ausdrücklich zeigen. Risiko mittel: höher als beim iPad mit Paket A, weil der Mac weniger Eigenes hat. Falls Apple ablehnt: Mac-Funktionen nachziehen, z.B. Tastatur-Kürzel für den Screen oder Teilen und Drucken. | – |

**Bundle-ID: dieselbe wie das iPad (`ch.klassentakt.app`), Empfehlung.**
- Vorteile: Universal Purchase heisst ein Eintrag für beide Geräte, mit gemeinsamen Bewertungen, Datenschutz-Angaben und Verfügbarkeit. Die App-ID hat «Sign in with Apple» schon als Primary. Die Electron-App heisst heute schon `ch.klassentakt.app`.
- Nachteile:
  - Wer die Download-Version installiert hat, muss sie löschen, bevor der App Store installiert. Es ist dieselbe ID, und der App Store sieht sie sonst als «schon installiert».
  - Die Anmeldung ist einmal neu nötig, weil die Sandbox eigene Daten hat.
- Lösung für den Übergang: eine letzte Download-Version 0.4.2 mit dem Hinweis «Klassentakt gibt es jetzt im App Store» und einem Link. Die ist optional und kommt erst, wenn der Store live ist.
- Eine eigene ID wie `ch.klassentakt.mac` hätte keinen Konflikt mit der Download-Version, dafür aber zwei Einträge, alles doppelt auszufüllen, und eine zweite App-ID im Apple-Login-Verbund. Das lohnt sich nicht.

---

## 2. Alternative: Mac Catalyst oder «Designed for iPad»

| | Electron `mas` (Empfehlung) | «Designed for iPad» auf Apple-Silicon-Macs | Mac Catalyst (iPad-Projekt für den Mac) |
|---|---|---|---|
| Aufwand bis TestFlight | ~3 T | ~0 (Häkchen in App Store Connect) | 3–5 T + 1–2 T für den Beamer |
| Beamer auf dem zweiten Bildschirm | ✅ vorhanden (Auswahl des Bildschirms, Vollbild) | ❌ Am Mac gibt es keine Szene für einen externen Bildschirm, der Screen bleibt im Fenster | 🟡 nur über ein eigenes AppKit-Plugin (Fenster auf einen bestimmten Bildschirm legen) |
| iPad-Funktionen aus Paket A | – | 🟡 Kamera ja, Dokumentenscanner (VisionKit) nein, Pencil nein | 🟡 wie links |
| Intel-Macs | ✅ (Universal-Build) | ❌ nur Apple Silicon | ✅ |
| Mac-Gefühl (Menüs, Fenster, Kürzel) | ✅ | ❌ iPad-Fenster | 🟡 mit Arbeit |
| Mit Apple anmelden | Web-Flow | nativ | nativ |
| Codebasis | Electron bleibt (gibt es schon) | eine (Swift) | eine (Swift); Electron fällt mittelfristig weg |
| 4.2-Risiko | mittel | hoch (iPad-App ohne Beamer am Mac) | mittel |

**Empfehlung:** Jetzt Electron `mas`. Die Mac-App bleibt dann, wie Florian und die Lehrpersonen sie kennen, mit dem Beamer, und der Aufwand ist am kleinsten. «Designed for iPad» bleibt **aus** (Entscheid vom 04.11.). Am Mac fehlt dort genau das, was die App im Unterricht ausmacht. Mac Catalyst kommt später auf den Tisch, wenn das iPad viele eigene Funktionen hat (Paket A und B) und eine einzige Swift-Codebasis mehr bringt als die Electron-Hülle. Frühestens nach der Freigabe beider Apps.

---

## 3. Umsetzung (eigener Branch `claude/mac-app-store`, nach OK der Leitung)
1. `package.json`: Ziel `mas` (universal), `mas`-Block mit Entitlements, `provisioningProfile`, `files` ohne Updater, `extendInfo` (Export Compliance, `LSApplicationCategoryType`).
2. `build/entitlements.mas.plist`, `build/entitlements.mas.inherit.plist`, eventuell `PrivacyInfo.xcprivacy`.
3. `src/main.js` / `src/preload.js`: `process.mas` → kein Updater, kein Menüpunkt, `features` ohne `update`.
4. Workflow-Job «Mac App Store»: Zertifikate aus Secrets in einen temporären Schlüsselbund, Profil aus dem Secret (base64, nicht im Repo), Build, `pkgutil --check-signature`, Upload zu TestFlight. Läuft nur, wenn die Secrets da sind, sonst wird er übersprungen, wie bei `ios.yml`.
5. Tests: `npm test` um die MAS-Konfiguration erweitern (Entitlements vorhanden, Updater im MAS-Build aus, gleiche Bundle-ID).
6. Screenshot-Skript 2880 × 1800.
7. `docs/AppStore-Launch.md` nachführen.

Zeit: **Fr 06.11.** Punkte 1–3, 5 · **Mo 09.11.** Punkt 4 und Upload-Runden, sobald die Secrets da sind · **Di 10.11.** Screenshots, TestFlight-Test mit Florian. Einreichung danach zusammen mit dem iPad oder kurz nach ihm, nur mit Florians Freigabe.

---

## 4. Was Florian selbst klicken muss (Geheimnisse nie ins Repo oder in den Chat)
1. **Zertifikat «Mac Installer Distribution»** (developer.apple.com → Certificates → «+» → «Mac Installer Distribution»). Die CSR erstellt er mit der Schlüsselbundverwaltung, lädt dann das .cer herunter, öffnet es doppelt und exportiert es als .p12 mit Passwort.
   «Apple Distribution» gibt es schon (iPad). Es gilt auch für Mac-App-Store-Apps, das vorhandene Secret lässt sich weiter verwenden.
2. **Provisioning-Profil** (Profiles → «+» → Distribution «Mac App Store Connect» → App-ID `ch.klassentakt.app` → Zertifikat «Apple Distribution» → Name «Klassentakt Mac App Store») → herunterladen.
3. **GitHub-Secrets** (Repo → Settings → Secrets → Actions):
   - `MAS_INSTALLER_P12_BASE64` = base64 der .p12 aus Schritt 1, Befehl: `base64 -i datei.p12 | pbcopy`
   - `MAS_INSTALLER_PASSWORD`
   - `MAS_PROFILE_BASE64` = base64 des Profils aus Schritt 2
   - Die bestehenden `IOS_CERT_P12_BASE64` und `APPLE_API_KEY_*` werden weiter verwendet.
4. **App Store Connect** → App «Klassentakt» → «+ Plattform» → **macOS** → Version 1.0.0. Mac-Screenshots hochladen, Mac-Texte ergänzen (Rest gilt vom iPad), «Designed for iPad» bleibt aus. Für die Prüfung: dasselbe Demo-Konto.
5. **TestFlight (Mac)**: interne Testgruppe, mit seiner Apple-ID testen. App «TestFlight» aus dem Mac App Store.
6. **Einreichen**: erst nach seiner Freigabe. Manuell veröffentlichen.
7. Danach: Lehrpersonen mit der Download-Version die Download-App löschen lassen, dann aus dem App Store installieren. Optional mit einem Hinweis in 0.4.2.
