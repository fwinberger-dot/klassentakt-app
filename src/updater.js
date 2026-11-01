// Selbst-Update der Mac-Hülle.
// Neue Versionen liegen als GitHub-Release (latest.json + zip). Die Web-App klassentakt.ch
// braucht kein Update – das hier betrifft nur die Hülle (neue Mac-Funktionen).
//
// Ablauf: latest.json holen → zip laden → SHA-256 prüfen → entpacken (ditto) →
// Hilfsskript wartet, bis die App beendet ist, tauscht die App aus und startet sie neu.
const { app, net, shell, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { execFile, spawn } = require('child_process');

const REPO = 'fwinberger-dot/klassentakt-app';
const LATEST_URL = `https://github.com/${REPO}/releases/latest/download/latest.json`;
const RELEASES_PAGE = `https://github.com/${REPO}/releases/latest`;

let busy = false;
let declined = null; // «Später» gilt bis zum nächsten App-Start
let getWin = () => null;

const newer = (a, b) => {
  const pa = String(a).split('.').map(Number), pb = String(b).split('.').map(Number);
  for (let i = 0; i < 3; i++) { if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0); }
  return false;
};

/** Pfad der laufenden App, z.B. /Applications/Klassentakt.app */
function bundlePath() {
  const p = path.resolve(process.execPath, '..', '..', '..');
  return p.endsWith('.app') ? p : null;
}

/** Kann die App sich selbst ersetzen? (nicht aus dem DMG, Ordner beschreibbar) */
function installProblem() {
  if (process.platform !== 'darwin') return 'Automatische Updates gibt es nur auf dem Mac.';
  if (!app.isPackaged) return 'Entwicklungsversion – kein Update.';
  const b = bundlePath();
  if (!b) return 'App-Ordner nicht gefunden.';
  if (b.startsWith('/Volumes/')) return 'Klassentakt läuft noch aus dem Installations-Fenster. Zieh die App zuerst in «Programme» und starte sie von dort.';
  if (b.includes('/AppTranslocation/')) {
    return 'macOS hat die App in einen Schutzordner verschoben. Zieh sie in «Programme» und starte sie von dort.';
  }
  try { fs.accessSync(path.dirname(b), fs.constants.W_OK); } catch { return 'Keine Schreibrechte im Programme-Ordner.'; }
  return null;
}

async function fetchLatest() {
  const res = await net.fetch(LATEST_URL + '?t=' + Date.now(), { cache: 'no-store' });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const info = await res.json();
  if (!info || !info.version || !info.url || !/^[a-f0-9]{64}$/.test(info.sha256 || '')) throw new Error('latest.json unvollständig');
  if (!/^https:\/\/github\.com\//.test(info.url)) throw new Error('Unerwartete Download-Adresse');
  return info;
}

/** zip herunterladen, Fortschritt im Dock, SHA-256 prüfen. */
async function download(info, file, onProgress = () => {}) {
  const res = await net.fetch(info.url, { cache: 'no-store' });
  if (!res.ok || !res.body) throw new Error('Download HTTP ' + res.status);
  const total = Number(res.headers.get('content-length')) || info.size || 0;
  const hash = crypto.createHash('sha256');
  const out = fs.createWriteStream(file);
  const reader = res.body.getReader();
  let got = 0;
  const win = getWin();
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = Buffer.from(value);
      hash.update(chunk);
      if (!out.write(chunk)) await new Promise((r) => out.once('drain', r));
      got += chunk.length;
      if (total) { const p = Math.min(1, got / total); onProgress(p); if (win && !win.isDestroyed()) win.setProgressBar(p); }
    }
  } finally {
    await new Promise((r) => out.end(r));
    if (win && !win.isDestroyed()) win.setProgressBar(-1);
  }
  if (hash.digest('hex') !== info.sha256) throw new Error('Prüfsumme stimmt nicht – Download beschädigt.');
}

const run = (cmd, args) => new Promise((ok, fail) => execFile(cmd, args, (e, _o, se) => (e ? fail(new Error(se || e.message)) : ok())));

/** Hilfsskript: warten bis App zu, alte App wegschieben, neue einsetzen, starten. Bei Fehler: alte zurück. */
function swapScript() {
  return `#!/bin/sh
PID="$1"; NEW="$2"; TARGET="$3"; WORK="$4"
i=0; while kill -0 "$PID" 2>/dev/null && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done
OLD="$WORK/alt.app"
if mv "$TARGET" "$OLD"; then
  if mv "$NEW" "$TARGET"; then
    xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
    rm -rf "$OLD"
  else
    mv "$OLD" "$TARGET"
  fi
fi
open "$TARGET"
rm -rf "$WORK"
`;
}

async function install(info, onProgress, onRestart = () => {}) {
  const target = bundlePath();
  const work = fs.mkdtempSync(path.join(app.getPath('temp'), 'klassentakt-update-'));
  const zip = path.join(work, 'update.zip');
  await download(info, zip, onProgress);
  const unpack = path.join(work, 'neu');
  fs.mkdirSync(unpack);
  await run('/usr/bin/ditto', ['-x', '-k', zip, unpack]);
  const name = fs.readdirSync(unpack).find((n) => n.endsWith('.app'));
  if (!name) throw new Error('Im Download ist keine App.');
  const fresh = path.join(unpack, name);
  if (!fs.existsSync(path.join(fresh, 'Contents', 'MacOS'))) throw new Error('Download ist keine gültige App.');
  fs.rmSync(zip, { force: true });
  const script = path.join(work, 'tauschen.sh');
  fs.writeFileSync(script, swapScript(), { mode: 0o755 });
  onRestart();
  await new Promise((r) => setTimeout(r, 1200)); // «Startet neu …» kurz zeigen
  spawn('/bin/sh', [script, String(process.pid), fresh, target, work], { detached: true, stdio: 'ignore' }).unref();
  app.quit();
}

/* ---------- Update-Fenster im Klassentakt-Look ---------- */
let upWin = null;
let current = null; // { state, info, problem, message }

function send(patch) {
  current = { ...current, ...patch };
  if (upWin && !upWin.isDestroyed()) upWin.webContents.send('update:state', current);
}

function openWindow(initial) {
  current = { installed: app.getVersion(), ...initial };
  if (upWin && !upWin.isDestroyed()) { send({}); upWin.show(); upWin.focus(); return; }
  const parent = getWin();
  upWin = new BrowserWindow({
    width: 440, height: 400, resizable: false, minimizable: false, maximizable: false, fullscreenable: false,
    show: false, title: 'Klassentakt-Update', titleBarStyle: 'hiddenInset', backgroundColor: '#fff4e6',
    parent: parent && !parent.isDestroyed() ? parent : undefined,
    webPreferences: { preload: path.join(__dirname, 'update-preload.js'), contextIsolation: true, sandbox: true },
  });
  upWin.loadFile(path.join(__dirname, 'update.html'));
  upWin.once('ready-to-show', () => { upWin.show(); });
  upWin.on('closed', () => {
    if (current && current.state === 'offer') declined = current.info.version;
    upWin = null;
  });
}

function wireIpc() {
  const ok = (e) => upWin && !upWin.isDestroyed() && e.sender === upWin.webContents;
  ipcMain.handle('update:get', (e) => (ok(e) ? current : null));
  ipcMain.handle('update:resize', (e, h) => { if (ok(e)) { const [w] = upWin.getContentSize(); upWin.setContentSize(w, Math.max(240, Math.min(640, Math.round(h)))); } });
  ipcMain.handle('update:choose', async (e, choice) => {
    if (!ok(e) || !current) return;
    if (choice === 'later' || choice === 'close') { if (current.state === 'offer') declined = current.info.version; upWin.close(); return; }
    if (choice === 'page') { shell.openExternal(RELEASES_PAGE); upWin.close(); return; }
    if (choice === 'install' && current.state === 'offer' && !current.problem) {
      send({ state: 'download', progress: 0 });
      try {
        let last = 0;
        await install(current.info, (p) => { if (p - last >= 0.01 || p === 1) { last = p; send({ progress: p }); } }, () => send({ state: 'restart' }));
      } catch (err) {
        send({ state: 'error', message: err.message });
      }
    }
  });
}

/** Nach Updates suchen. manual=true: Fenster auch bei «aktuell» oder Fehler (Menü). */
async function check(manual) {
  if (busy) return;
  busy = true;
  try {
    let info;
    try { info = await fetchLatest(); } catch (e) {
      if (manual) openWindow({ state: 'checkfail', message: e.message });
      return;
    }
    if (!newer(info.version, app.getVersion())) {
      if (manual) openWindow({ state: 'current' });
      return;
    }
    if (!manual && declined === info.version) return;
    openWindow({ state: 'offer', info, problem: installProblem() });
  } finally { busy = false; }
}

function init(winGetter) { getWin = winGetter || getWin; wireIpc(); }

module.exports = { init, check, newer, bundlePath, installProblem, swapScript, LATEST_URL };
