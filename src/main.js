// Klassentakt – Mac-Hülle (Electron)
// Lädt klassentakt.ch in einem eigenen App-Fenster. Spätere Funktionen
// (Beamer-Steuerung, Webseiten einbetten) docken über die Brücke in preload.js an.
const { app, BrowserWindow, Menu, shell, session, dialog, systemPreferences, net } = require('electron');
const path = require('path');
const fs = require('fs');

const START_URL = 'https://klassentakt.ch/';
const UPDATE_URL = 'https://klassentakt.ch/app/version.json';
const APP_HOSTS = ['klassentakt.ch'];
// Login-Anbieter dürfen im App-Fenster (als Pop-up) laufen.
const LOGIN_HOSTS = ['jobnavigator.ch', 'accounts.google.com', 'login.microsoftonline.com', 'login.live.com', 'login.microsoft.com'];

const hostOf = (u) => { try { return new URL(u).hostname; } catch { return ''; } };
const matches = (host, list) => list.some((h) => host === h || host.endsWith('.' + h));
const isApp = (u) => matches(hostOf(u), APP_HOSTS);
const isLogin = (u) => matches(hostOf(u), LOGIN_HOSTS);

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

/* ---------- Hauptfenster ---------- */
function createWindow() {
  const st = loadState();
  win = new BrowserWindow({
    x: st.x, y: st.y, width: st.width || 1360, height: st.height || 860,
    minWidth: 900, minHeight: 600,
    title: 'Klassentakt',
    backgroundColor: '#fff4e6',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
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
  win.loadURL(START_URL);
}

/* ---------- Navigation: Klassentakt im Fenster, alles andere im Browser ---------- */
function wireNavigation(wc) {
  wc.setWindowOpenHandler(({ url }) => {
    if (isApp(url) || isLogin(url)) {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: {
          width: 1100, height: 780, autoHideMenuBar: true,
          webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
        },
      };
    }
    if (/^https?:|^mailto:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  wc.on('will-navigate', (e, url) => {
    if (url.startsWith('file:') || isApp(url) || isLogin(url)) return;
    e.preventDefault();
    if (/^https?:|^mailto:/.test(url)) shell.openExternal(url);
  });
  wc.on('did-create-window', (child) => wireNavigation(child.webContents));
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

/* ---------- Update-Check (klassentakt.ch/app/version.json) ---------- */
const newer = (a, b) => {
  const pa = String(a).split('.').map(Number), pb = String(b).split('.').map(Number);
  for (let i = 0; i < 3; i++) { if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0); }
  return false;
};
async function checkUpdate(manual) {
  try {
    const res = await net.fetch(UPDATE_URL + '?t=' + Date.now(), { cache: 'no-store' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const info = (await res.json()).mac || {};
    if (info.version && newer(info.version, app.getVersion())) {
      const { response } = await dialog.showMessageBox(win, {
        type: 'info', buttons: ['Herunterladen', 'Später'], defaultId: 0, cancelId: 1,
        message: `Klassentakt ${info.version} ist da`,
        detail: (info.notes ? info.notes + '\n\n' : '') + `Installiert ist ${app.getVersion()}.`,
      });
      if (response === 0 && info.url) shell.openExternal(info.url);
    } else if (manual) {
      dialog.showMessageBox(win, { type: 'info', message: 'Klassentakt ist aktuell', detail: `Version ${app.getVersion()}` });
    }
  } catch (e) {
    if (manual) dialog.showMessageBox(win, { type: 'warning', message: 'Update-Prüfung nicht möglich', detail: 'Bitte später nochmals versuchen.' });
  }
}

/* ---------- Menü ---------- */
function buildMenu() {
  const t = [
    {
      label: 'Klassentakt',
      submenu: [
        { role: 'about', label: 'Über Klassentakt' },
        { label: 'Nach Updates suchen …', click: () => checkUpdate(true) },
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
    { role: 'windowMenu', label: 'Fenster' },
    { role: 'help', label: 'Hilfe', submenu: [{ label: 'klassentakt.ch im Browser öffnen', click: () => shell.openExternal(START_URL) }] },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(t));
}

/* ---------- Start ---------- */
app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
app.whenReady().then(() => {
  app.setAboutPanelOptions({ applicationName: 'Klassentakt', applicationVersion: app.getVersion(), copyright: '© 2026 Florian Winberger', website: START_URL });
  wirePermissions();
  buildMenu();
  createWindow();
  setTimeout(() => checkUpdate(false), 8000);
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
