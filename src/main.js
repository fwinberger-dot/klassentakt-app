// Klassentakt – Mac-Hülle (Electron)
// Lädt klassentakt.ch in einem eigenen App-Fenster. Spätere Funktionen
// (Beamer-Steuerung, Webseiten einbetten) docken über die Brücke in preload.js an.
const { app, BrowserWindow, Menu, shell, session, dialog, systemPreferences, ipcMain, net } = require('electron');
const path = require('path');
const fs = require('fs');
const beamer = require('./beamer');
// Mac App Store (process.mas): Apple aktualisiert die App, darum dort kein eigenes Update (Dateien fehlen im Paket).
const updater = process.mas ? null : require('./updater');
const { createInk, binPath } = require('./ink');
const ink = createInk(binPath(app));

const server = require('./server');
const START_URL = server.startUrl(); // klassentakt.ch, zum Testen auch staging (siehe server.js)
const APP_HOSTS = ['klassentakt.ch'];
// Login-Anbieter dürfen im App-Fenster laufen. Google NICHT: Google blockiert
// Logins in App-Fenstern («Browser nicht sicher»), darum läuft Google im Systembrowser.
const LOGIN_HOSTS = ['jobnavigator.ch', 'login.microsoftonline.com', 'login.live.com', 'login.microsoft.com'];
const PROTOCOL = 'klassentakt';
// Anbieter, deren Login im Systembrowser läuft und per klassentakt://auth?code=… zurückkommt.
const EXTERNAL_LOGIN = ['google'];

const hostOf = (u) => { try { return new URL(u).hostname; } catch { return ''; } };
const matches = (host, list) => list.some((h) => host === h || host.endsWith('.' + h));
const isApp = (u) => matches(hostOf(u), APP_HOSTS);
const isLogin = (u) => matches(hostOf(u), LOGIN_HOSTS);
const isGoogleAuth = (u) => matches(hostOf(u), ['accounts.google.com']);

/* ---------- Login im Systembrowser ---------- */
// Erkennt https://klassentakt.ch/auth/<anbieter>/start?next=… für Anbieter aus EXTERNAL_LOGIN.
function externalLoginUrl(u) {
  try {
    const url = new URL(u);
    if (!isApp(u)) return null;
    const m = url.pathname.match(/^\/auth\/([a-z]+)\/start\/?$/);
    if (!m || !EXTERNAL_LOGIN.includes(m[1])) return null;
    url.searchParams.set('app', '1');
    return url.toString();
  } catch { return null; }
}
// Kann klassentakt.ch den Login aus dem Browser schon an die App zurückgeben?
// Solange /auth/app/redeem 404 liefert (Server-Teil fehlt), zeigen wir eine klare Info statt eines toten Browser-Logins.
async function appLoginSupported() {
  try { const r = await net.fetch(START_URL + 'auth/app/redeem?probe=1', { cache: 'no-store', redirect: 'manual' }); return r.status !== 404; }
  catch { return false; }
}
let googleBusy = false;
async function startExternalLogin(url, fromWc) {
  // Login-Popup (z.B. Jobnavigator) schliessen, damit kein zweites Fenster hängen bleibt
  if (fromWc && win && fromWc !== win.webContents) { const w = BrowserWindow.fromWebContents(fromWc); if (w && !w.isDestroyed()) w.close(); }
  if (googleBusy) return; googleBusy = true;
  try {
    const ok = await appLoginSupported();
    if (!win || win.isDestroyed()) createWindow();
    if (ok) { shell.openExternal(url); win.loadFile(path.join(__dirname, 'login-extern.html')); }
    else win.loadFile(path.join(__dirname, 'login-extern.html'), { query: { modus: 'bald' } });
    win.show(); win.focus();
  } finally { setTimeout(() => { googleBusy = false; }, 1500); }
}
// klassentakt://auth?code=…&next=/… → Code auf klassentakt.ch einlösen (setzt das Login-Cookie in der App).
function handleDeepLink(raw) {
  try {
    const u = new URL(raw);
    if (u.protocol !== PROTOCOL + ':' || u.hostname !== 'auth') return;
    const code = u.searchParams.get('code') || '';
    if (!/^[A-Za-z0-9_-]{16,200}$/.test(code)) return;
    let next = u.searchParams.get('next') || '/';
    if (!next.startsWith('/') || next.startsWith('//')) next = '/';
    const target = `${START_URL}auth/app/redeem?code=${encodeURIComponent(code)}&next=${encodeURIComponent(next)}`;
    if (!win || win.isDestroyed()) createWindow(target); else win.loadURL(target);
    if (win.isMinimized()) win.restore();
    win.show(); win.focus(); app.focus({ steal: true });
  } catch {}
}

// Google blockiert Logins in Fenstern, die sich als «Electron» ausweisen.
// Darum melden wir uns als normales Chrome.
app.userAgentFallback = app.userAgentFallback
  .replace(/\sElectron\/\S+/, '')
  .replace(/\s\S*klassentakt\S*\/\S+/i, '');

if (!app.requestSingleInstanceLock()) { app.quit(); }

let win = null;

/* ---------- Fenstergrösse merken ---------- */
const stateFile = () => path.join(app.getPath('userData'), 'fenster.json');
function loadState() {
  try { return JSON.parse(fs.readFileSync(stateFile(), 'utf8')); } catch { return { width: 1360, height: 860 }; }
}
function saveState() {
  if (!win || win.isDestroyed() || win.isFullScreen()) return;
  try { fs.writeFileSync(stateFile(), JSON.stringify({ ...win.getNormalBounds(), maximized: win.isMaximized() })); } catch {}
}

/** Angaben für preload.js (die Brücke läuft in der Sandbox und kann selbst nichts nachsehen). */
const shellArgs = () => [`--kt-shell-version=${app.getVersion()}`, ...(ink.available() ? ['--kt-ink'] : [])];

/* ---------- Hauptfenster ---------- */
function createWindow(startUrl) {
  const st = loadState();
  win = new BrowserWindow({
    x: st.x, y: st.y, width: st.width || 1360, height: st.height || 860,
    minWidth: 900, minHeight: 600,
    title: 'Klassentakt',
    backgroundColor: '#fff4e6',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'), additionalArguments: shellArgs(),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: true,
    },
  });
  if (st.maximized) win.maximize();
  win.once('ready-to-show', () => win.show());
  ['resize', 'move', 'close'].forEach((ev) => win.on(ev, saveState));

  wireNavigation(win.webContents);
  win.webContents.on('did-fail-load', (_e, code, _desc, url, isMain) => {
    if (isMain && code !== -3) win.loadFile(path.join(__dirname, 'offline.html'), { query: { ziel: url || START_URL } });
  });
  win.loadURL(startUrl || START_URL);
}

/* ---------- Navigation: Klassentakt im Fenster, alles andere im Browser ---------- */
function wireNavigation(wc) {
  wc.setWindowOpenHandler(({ url, frameName }) => {
    const ext = externalLoginUrl(url);
    if (ext) { startExternalLogin(ext, wc); return { action: 'deny' }; }
    if (isGoogleAuth(url)) { startExternalLogin(START_URL + 'auth/google/start?next=%2F&app=1', wc); return { action: 'deny' }; }
    const blank = !url || url === 'about:blank';
    // Classroom Screen: eigenes Fenster, später auf den Beamer (siehe did-create-window)
    if ((isApp(url) || blank) && beamer.isScreenRequest(url, frameName)) {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: {
          ...beamer.windowOptions(win),
          webPreferences: { preload: path.join(__dirname, 'preload.js'), additionalArguments: shellArgs(), contextIsolation: true, sandbox: true },
        },
      };
    }
    if (isApp(url) || isLogin(url) || blank) {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: {
          width: 1100, height: 780, autoHideMenuBar: true,
          webPreferences: { preload: path.join(__dirname, 'preload.js'), additionalArguments: shellArgs(), contextIsolation: true, sandbox: true },
        },
      };
    }
    if (/^https?:|^mailto:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  const guard = (e, url) => {
    const ext = externalLoginUrl(url);
    if (ext) { e.preventDefault(); startExternalLogin(ext, wc); return; }
    if (isGoogleAuth(url)) { // Umleitung zu Google ohne unseren Start-Link: Login neu im Browser starten
      e.preventDefault();
      startExternalLogin(START_URL + 'auth/google/start?next=%2F&app=1', wc);
      return;
    }
    if (isApp(url) && /[?&]im-browser=1/.test(url)) { e.preventDefault(); shell.openExternal(START_URL); return; }
    if (url.startsWith('file:') || isApp(url) || isLogin(url)) return;
    e.preventDefault();
    if (/^https?:|^mailto:/.test(url)) shell.openExternal(url);
  };
  wc.on('will-navigate', guard);
  wc.on('will-redirect', guard);
  wc.on('did-create-window', (child, details) => {
    wireNavigation(child.webContents);
    if (beamer.isScreenRequest(details.url, details.frameName)) beamer.adopt(child, win);
  });
}

/* ---------- Berechtigungen: nur für Klassentakt ---------- */
function wirePermissions() {
  const ok = ['media', 'fullscreen', 'clipboard-sanitized-write', 'notifications', 'screen-wake-lock', 'idle-detection'];
  session.defaultSession.setPermissionRequestHandler(async (wc, perm, cb, details) => {
    const origin = details.requestingUrl || wc.getURL();
    if (!isApp(origin) || !ok.includes(perm)) return cb(false);
    if (perm === 'media' && process.platform === 'darwin') {
      const types = details.mediaTypes || [];
      try {
        if (types.includes('audio')) await systemPreferences.askForMediaAccess('microphone');
        if (types.includes('video')) await systemPreferences.askForMediaAccess('camera');
      } catch {}
    }
    cb(true);
  });
  session.defaultSession.setPermissionCheckHandler((_wc, perm, origin) => isApp(origin) && ok.includes(perm));
}

/* ---------- Beamer-Menü (wird bei jeder Änderung neu aufgebaut) ---------- */
function beamerMenu() {
  const s = beamer.state();
  const shows = s.displays.map((d) => ({
    label: d.label + (d.primary ? ' (Hauptbildschirm)' : ''),
    type: 'radio',
    checked: s.open ? s.onDisplay === d.id : (s.settings.displayId ? s.settings.displayId === d.id : d.primary && s.displays.length === 1),
    enabled: s.open,
    click: () => beamer.moveTo(d.id),
  }));
  return {
    label: 'Beamer',
    submenu: [
      { label: s.open ? 'Classroom Screen ist offen' : 'Classroom Screen ist nicht offen', enabled: false },
      { label: 'Screen auf nächsten Bildschirm', accelerator: 'CmdOrCtrl+Shift+B', enabled: s.open && s.displays.length > 1, click: () => beamer.moveNext() },
      { label: 'Screen-Vollbild an/aus', accelerator: 'CmdOrCtrl+Shift+F', enabled: s.open, click: () => beamer.toggleFullscreen() },
      { label: 'Screen steuern', accelerator: 'CmdOrCtrl+Shift+S', enabled: s.open, click: () => shellCommand('screen-control') },
      { type: 'separator' },
      { label: 'Screen anzeigen auf', enabled: s.open && s.displays.length > 1, submenu: shows.length ? shows : [{ label: 'Kein Bildschirm', enabled: false }] },
      { type: 'separator' },
      { label: 'Screen automatisch auf den Beamer', type: 'checkbox', checked: s.settings.auto, click: (i) => beamer.setSetting('auto', i.checked) },
      { label: 'Auf dem Beamer im Vollbild', type: 'checkbox', checked: s.settings.fullscreen, click: (i) => beamer.setSetting('fullscreen', i.checked) },
      { label: 'Mac wach halten, solange der Screen offen ist', type: 'checkbox', checked: s.settings.keepAwake, click: (i) => beamer.setSetting('keepAwake', i.checked) },
      { type: 'separator' },
      { label: s.displays.length > 1 ? `${s.displays.length} Bildschirme erkannt` : 'Nur ein Bildschirm erkannt (Beamer gespiegelt oder nicht angeschlossen)', enabled: false },
    ],
  };
}

/* ---------- Brücke für die Web-App (window.klassentaktShell.beamer) ---------- */
function wireBridge() {
  const fromApp = (e) => isApp(e.senderFrame ? e.senderFrame.url : e.sender.getURL());
  ipcMain.handle('beamer:state', (e) => (fromApp(e) ? beamer.state() : null));
  ipcMain.handle('beamer:moveTo', (e, id) => (fromApp(e) ? beamer.moveTo(Number(id)) : false));
  ipcMain.handle('beamer:next', (e) => (fromApp(e) ? beamer.moveNext() : false));
  ipcMain.handle('beamer:fullscreen', (e) => (fromApp(e) ? beamer.toggleFullscreen() : false));
  // send/on: Nachrichten der Web-App; die Antwort geht an das Fenster, das gefragt hat
  ipcMain.on('shell:send', (e, name, payload) => {
    if (!fromApp(e)) return;
    const wc = e.sender;
    if (name === 'recognize-ink') ink.recognize(payload, (r) => { if (!wc.isDestroyed()) wc.send('shell:event', 'ink-text', r); });
  });
}
/** Befehl an die Web-App im Hauptfenster (Planer), nicht ans Screen-Fenster. */
function shellCommand(name) {
  try { if (win && !win.isDestroyed() && isApp(win.webContents.getURL())) win.webContents.send('shell:command', { name }); } catch {}
}
function broadcastBeamer() {
  const st = beamer.state();
  BrowserWindow.getAllWindows().forEach((w) => { try { if (isApp(w.webContents.getURL())) w.webContents.send('beamer:changed', st); } catch {} });
}

/* ---------- Menü ---------- */
function buildMenu() {
  const t = [
    {
      label: 'Klassentakt',
      submenu: [
        { role: 'about', label: 'Über Klassentakt' },
        ...(updater ? [{ label: 'Nach Updates suchen …', click: () => updater.check(true) }] : []),
        { type: 'separator' },
        { role: 'services', label: 'Dienste' },
        { type: 'separator' },
        { role: 'hide', label: 'Klassentakt ausblenden' },
        { role: 'hideOthers', label: 'Andere ausblenden' },
        { role: 'unhide', label: 'Alle einblenden' },
        { type: 'separator' },
        { role: 'quit', label: 'Klassentakt beenden' },
      ],
    },
    {
      label: 'Bearbeiten',
      submenu: [
        { role: 'undo', label: 'Widerrufen' }, { role: 'redo', label: 'Wiederholen' }, { type: 'separator' },
        { role: 'cut', label: 'Ausschneiden' }, { role: 'copy', label: 'Kopieren' }, { role: 'paste', label: 'Einsetzen' },
        { role: 'selectAll', label: 'Alles auswählen' },
      ],
    },
    {
      label: 'Darstellung',
      submenu: [
        { role: 'reload', label: 'Neu laden' },
        { label: 'Zur Startseite', accelerator: 'CmdOrCtrl+Shift+H', click: () => win && win.loadURL(START_URL) },
        { type: 'separator' },
        { role: 'resetZoom', label: 'Originalgrösse' }, { role: 'zoomIn', label: 'Vergrössern' }, { role: 'zoomOut', label: 'Verkleinern' },
        { type: 'separator' },
        { role: 'togglefullscreen', label: 'Vollbild' },
        { role: 'toggleDevTools', label: 'Entwicklerwerkzeuge' },
      ],
    },
    {
      label: 'Navigation',
      submenu: [
        { label: 'Zurück', accelerator: 'CmdOrCtrl+[', click: () => win && win.webContents.navigationHistory.canGoBack() && win.webContents.navigationHistory.goBack() },
        { label: 'Vorwärts', accelerator: 'CmdOrCtrl+]', click: () => win && win.webContents.navigationHistory.canGoForward() && win.webContents.navigationHistory.goForward() },
      ],
    },
    beamerMenu(),
    { role: 'windowMenu', label: 'Fenster' },
    { role: 'help', label: 'Hilfe', submenu: [{ label: 'klassentakt.ch im Browser öffnen', click: () => shell.openExternal(START_URL) }, { type: 'separator' }, { label: `App-Version ${app.getVersion()}`, enabled: false }] },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(t));
}

/* ---------- Start ---------- */
// klassentakt://-Links (Rückkehr vom Login im Browser)
if (process.defaultApp && process.argv.length >= 2) {
  app.setAsDefaultProtocolClient(PROTOCOL, process.execPath, [path.resolve(process.argv[1])]);
} else {
  app.setAsDefaultProtocolClient(PROTOCOL);
}
let pendingLink = null;
app.on('open-url', (e, url) => { e.preventDefault(); if (app.isReady() && win) handleDeepLink(url); else pendingLink = url; });
app.on('second-instance', (_e, argv) => {
  const link = argv.find((a) => a.startsWith(PROTOCOL + '://'));
  if (link) return handleDeepLink(link);
  if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
});
app.whenReady().then(() => {
  app.setAboutPanelOptions({ applicationName: 'Klassentakt', applicationVersion: app.getVersion(), copyright: '© 2026 Florian Winberger', website: START_URL });
  wirePermissions();
  if (updater) updater.init(() => win);
  beamer.init(() => { buildMenu(); broadcastBeamer(); });
  wireBridge();
  buildMenu();
  createWindow();
  if (pendingLink) { handleDeepLink(pendingLink); pendingLink = null; }
  if (updater) {
    setTimeout(() => updater.check(false), 8000);
    setInterval(() => updater.check(false), 6 * 60 * 60 * 1000); // App läuft oft tagelang
  }
  app.on('will-quit', () => ink.stop());
  // staging fragt nach Basic-Auth: Zugang nur aus KT_BASIC und nur für den Testserver
  app.on('login', (e, _wc, _details, auth, cb) => {
    const z = !auth.isProxy && server.basicFor(auth.host);
    if (z) { e.preventDefault(); cb(z.username, z.password); }
  });
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
