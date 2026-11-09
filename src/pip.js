// Schwebende Vorschau (Bild im Bild): window.open('about:blank','ktfloat',…) des Planers wird zu einem
// Fenster, das immer obenauf liegt, auf allen Spaces und über Vollbild-Apps. Es bleibt ein normales
// Electron-Kindfenster (window.opener, BroadcastChannel, gleiche Session) – die Seite zeichnet selbst hinein.
const { app, screen } = require('electron');
const path = require('path');
const fs = require('fs');

const NAME = 'ktfloat';
const DEFAULT_SIZE = { width: 480, height: 353 };
const MIN = { width: 260, height: 200 };
let pipWin = null;
let onChange = () => {};

const file = () => path.join(app.getPath('userData'), 'pip.json');
function loadPos() { try { return JSON.parse(fs.readFileSync(file(), 'utf8')); } catch { return null; } }
function savePos() {
  if (!pipWin || pipWin.isDestroyed()) return;
  try { const { x, y } = pipWin.getBounds(); fs.writeFileSync(file(), JSON.stringify({ x, y })); } catch {}
}

const isPipRequest = (frameName) => String(frameName || '') === NAME;

/** Breite/Höhe aus den window.open-Features (width=…,height=…), mindestens MIN. */
function sizeFrom(features) {
  const f = {};
  String(features || '').split(',').forEach((p) => { const [k, v] = p.split('='); if (k) f[k.trim()] = Number(v); });
  const w = Number.isFinite(f.width) && f.width > 0 ? f.width : DEFAULT_SIZE.width;
  const h = Number.isFinite(f.height) && f.height > 0 ? f.height : DEFAULT_SIZE.height;
  return { width: Math.max(MIN.width, Math.round(w)), height: Math.max(MIN.height, Math.round(h)) };
}

/** Gemerkter Ort, falls noch auf einem Bildschirm; sonst unten rechts. `areas` = workAreas. */
function pickPosition(saved, size, areas) {
  if (saved && Number.isFinite(saved.x) && Number.isFinite(saved.y)) {
    const c = { x: saved.x + size.width / 2, y: saved.y + size.height / 2 };
    if (areas.some((d) => c.x >= d.x && c.x < d.x + d.width && c.y >= d.y && c.y < d.y + d.height)) return { x: Math.round(saved.x), y: Math.round(saved.y) };
  }
  const wa = areas[0] || { x: 0, y: 0, width: 1440, height: 900 };
  return { x: wa.x + wa.width - size.width - 24, y: wa.y + wa.height - size.height - 24 };
}

/** Fensteroptionen für setWindowOpenHandler. */
function windowOptions(features, webPreferences) {
  const size = sizeFrom(features);
  const pos = pickPosition(loadPos(), size, screen.getAllDisplays().map((d) => d.workArea));
  return {
    ...pos, ...size,
    minWidth: MIN.width, minHeight: MIN.height,
    title: 'Klassentakt – Vorschau',
    backgroundColor: '#10221d',
    autoHideMenuBar: true,
    minimizable: false, maximizable: false, fullscreenable: false,
    alwaysOnTop: true,
    webPreferences,
  };
}

/** Nach dem Öffnen: obenauf, auf allen Spaces, Ort merken. */
function adopt(child) {
  if (pipWin && !pipWin.isDestroyed() && pipWin !== child) pipWin.close(); // nur eine Vorschau
  pipWin = child;
  child.setAlwaysOnTop(true, 'floating');
  child.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true, skipTransformProcessType: true });
  child.on('move', savePos);
  child.on('closed', () => { if (pipWin === child) pipWin = null; onChange(); });
  onChange();
}

function close() {
  if (!pipWin || pipWin.isDestroyed()) return false;
  savePos();
  pipWin.close();
  return true;
}

const state = () => ({ open: !!(pipWin && !pipWin.isDestroyed()) });
function init(changed) { onChange = changed || (() => {}); }

module.exports = { NAME, init, isPipRequest, windowOptions, adopt, close, state, sizeFrom, pickPosition, DEFAULT_SIZE, MIN, get pipWin() { return pipWin; } };
