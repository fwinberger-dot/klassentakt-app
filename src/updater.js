// Selbst-Update der Mac-Hülle.
// Neue Versionen liegen als GitHub-Release (latest.json + zip). Die Web-App klassentakt.ch
// braucht kein Update – das hier betrifft nur die Hülle (neue Mac-Funktionen).
//
// Ablauf: latest.json holen → zip laden → SHA-256 prüfen → entpacken (ditto) →
// Hilfsskript wartet, bis die App beendet ist, tauscht die App aus und startet sie neu.
const { app, dialog, net, shell } = require('electron');
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
async function download(info, file) {
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
      if (win && !win.isDestroyed() && total) win.setProgressBar(Math.min(1, got / total));
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

async function install(info) {
  const target = bundlePath();
  const work = fs.mkdtempSync(path.join(app.getPath('temp'), 'klassentakt-update-'));
  const zip = path.join(work, 'update.zip');
  await download(info, zip);
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
  spawn('/bin/sh', [script, String(process.pid), fresh, target, work], { detached: true, stdio: 'ignore' }).unref();
  app.quit();
}

/**
 * Nach Updates suchen. manual=true: auch «aktuell»/Fehler melden (Menü).
 */
async function check(manual) {
  if (busy) return;
  busy = true;
  const win = getWin();
  try {
    let info;
    try { info = await fetchLatest(); } catch (e) {
      if (manual) await dialog.showMessageBox(win, { type: 'warning', message: 'Update-Prüfung nicht möglich', detail: 'Bitte später nochmals versuchen.\n\n' + e.message });
      return;
    }
    if (!newer(info.version, app.getVersion())) {
      if (manual) await dialog.showMessageBox(win, { type: 'info', message: 'Klassentakt ist aktuell', detail: `Version ${app.getVersion()}` });
      return;
    }
    if (!manual && declined === info.version) return;
    const problem = installProblem();
    const { response } = await dialog.showMessageBox(win, {
      type: 'info',
      buttons: problem ? ['Download-Seite öffnen', 'Später'] : ['Jetzt aktualisieren', 'Später'],
      defaultId: 0, cancelId: 1,
      message: `Klassentakt ${info.version} ist da`,
      detail: (info.notes ? info.notes.trim() + '\n\n' : '') + `Installiert ist ${app.getVersion()}.` +
        (problem ? '\n\n' + problem : '\n\nDie App lädt das Update, schliesst sich kurz und startet neu.'),
    });
    if (response !== 0) { declined = info.version; return; }
    if (problem) { shell.openExternal(RELEASES_PAGE); return; }
    try { await install(info); } catch (e) {
      const r = await dialog.showMessageBox(win, {
        type: 'warning', buttons: ['Download-Seite öffnen', 'Schliessen'], defaultId: 0, cancelId: 1,
        message: 'Update fehlgeschlagen', detail: e.message + '\n\nDu kannst die neue Version auch von Hand installieren.',
      });
      if (r.response === 0) shell.openExternal(RELEASES_PAGE);
    }
  } finally { busy = false; }
}

function init(winGetter) { getWin = winGetter || getWin; }

module.exports = { init, check, newer, bundlePath, installProblem, swapScript, LATEST_URL };
