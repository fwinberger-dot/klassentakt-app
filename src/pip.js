// Schwebende Vorschau (Bild im Bild): eigenes Fenster, immer obenauf, auf allen Spaces, frei skalierbar.
// Die Web-App fordert es über window.klassentaktShell.pip an; das Fenster zeigt dieselbe Vorschau-Seite.
const { app, screen, BrowserWindow } = require('electron');
const path = require('path');
const fs = require('fs');

const DEFAULT_SIZE = { width: 480, height: 300 };
const MIN = { width: 240, height: 150 };
let pipWin = null;
let onChange = () => {};

const file = () => path.join(app.getPath('userData'), 'pip.json');
function loadBounds() { try { return JSON.parse(fs.readFileSync(file(), 'utf8')); } catch { return null; } }
function saveBounds() {
  if (!pipWin || pipWin.isDestroyed()) return;
  try { fs.writeFileSync(file(), JSON.stringify(pipWin.getBounds())); } catch {}
}

/** Gemerkte Grösse und Ort, aber nur wenn das Fenster noch auf einem angeschlossenen Bildschirm läge. */
function pickBounds(saved, displays) {
  const size = { width: DEFAULT_SIZE.width, height: DEFAULT_SIZE.height };
  if (saved && Number.isFinite(saved.width) && Number.isFinite(saved.height)) {
    size.width = Math.max(MIN.width, Math.round(saved.width));
    size.height = Math.max(MIN.height, Math.round(saved.height));
    if (Number.isFinite(saved.x) && Number.isFinite(saved.y)) {
      const c = { x: saved.x + size.width / 2, y: saved.y + size.height / 2 };
      const on = displays.some((d) => c.x >= d.x && c.x < d.x + d.width && c.y >= d.y && c.y < d.y + d.height);
      if (on) return { x: Math.round(saved.x), y: Math.round(saved.y), ...size };
    }
  }
  const wa = (displays[0] || { x: 0, y: 0, width: 1440, height: 900 });
  return { x: wa.x + wa.width - size.width - 24, y: wa.y + wa.height - size.height - 24, ...size };
}

function state() {
  const open = !!(pipWin && !pipWin.isDestroyed());
  return { open, bounds: open ? pipWin.getBounds() : null };
}

/** Vorschau öffnen (oder nach vorn holen, falls schon offen). `onCreate(win)` darf das neue Fenster verdrahten. */
function open(url, webPreferences, onCreate) {
  if (pipWin && !pipWin.isDestroyed()) { pipWin.showInactive(); if (pipWin.webContents.getURL() !== url) pipWin.loadURL(url); return true; }
  const b = pickBounds(loadBounds(), screen.getAllDisplays().map((d) => d.workArea));
  pipWin = new BrowserWindow({
    ...b,
    minWidth: MIN.width, minHeight: MIN.height,
    title: 'Klassentakt – Vorschau',
    backgroundColor: '#10221d',
    autoHideMenuBar: true,
    minimizable: false, maximizable: false, fullscreenable: false,
    alwaysOnTop: true,
    show: false,
    webPreferences,
  });
  const w = pipWin;
  // Über Word, Browser und Vollbild-Apps, auf jedem Space
  w.setAlwaysOnTop(true, 'floating');
  w.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true, skipTransformProcessType: true });
  w.once('ready-to-show', () => w.showInactive());
  ['resize', 'move'].forEach((ev) => w.on(ev, saveBounds));
  w.on('closed', () => { if (pipWin === w) pipWin = null; onChange(); });
  if (onCreate) onCreate(w);
  w.loadURL(url);
  onChange();
  return true;
}

function close() {
  if (!pipWin || pipWin.isDestroyed()) return false;
  saveBounds();
  pipWin.close();
  return true;
}

function init(changed) { onChange = changed || (() => {}); }

module.exports = { init, open, close, state, pickBounds, DEFAULT_SIZE, MIN, get pipWin() { return pipWin; } };
