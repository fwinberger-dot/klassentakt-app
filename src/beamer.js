// Beamer-Steuerung: Classroom-Screen-Fenster auf den Beamer, Vollbild, wach halten.
// Erkennt das Screen-Fenster am Link (?classroom=1) oder am Fensternamen (wp_classroom…),
// den klassentakt.ch beim Öffnen des Screens verwendet. Keine Änderung an der Web-App nötig.
const { app, screen, powerSaveBlocker, BrowserWindow } = require('electron');
const path = require('path');
const fs = require('fs');

const settingsFile = () => path.join(app.getPath('userData'), 'beamer.json');
const DEFAULTS = { auto: true, fullscreen: true, keepAwake: true, displayId: null };
let settings = { ...DEFAULTS };
let screenWin = null;
let blockerId = null;
let onChange = () => {};

function load() { try { settings = { ...DEFAULTS, ...JSON.parse(fs.readFileSync(settingsFile(), 'utf8')) }; } catch {} }
function save() { try { fs.writeFileSync(settingsFile(), JSON.stringify(settings)); } catch {} }

/** Ist das ein Screen-Fenster von Klassentakt? */
function isScreenRequest(url, frameName) {
  const name = String(frameName || '');
  if (/^wp_(classroom|cs_)/.test(name)) return true;
  try { return new URL(url).searchParams.get('classroom') === '1'; } catch { return false; }
}

/** Alle Bildschirme mit lesbarem Namen. */
function listDisplays() {
  const primary = screen.getPrimaryDisplay();
  return screen.getAllDisplays().map((d, i) => ({
    id: d.id,
    label: d.label || (d.internal ? 'Eingebauter Bildschirm' : `Bildschirm ${i + 1}`),
    primary: d.id === primary.id,
    internal: !!d.internal,
    bounds: d.bounds,
    workArea: d.workArea,
  }));
}

/**
 * Bildschirm für den Screen wählen:
 * 1. vom Benutzer gewählter Bildschirm, falls angeschlossen
 * 2. sonst ein externer (nicht eingebauter, nicht primärer) Bildschirm
 * 3. sonst einer, auf dem das Hauptfenster nicht liegt
 * 4. sonst der primäre (nur ein Bildschirm)
 */
function pickDisplay(displays, mainBounds, preferredId) {
  if (!displays.length) return null;
  const pref = displays.find((d) => d.id === preferredId);
  if (pref) return pref;
  const external = displays.filter((d) => !d.internal && !d.primary);
  if (external.length) return external[0];
  const notMain = mainBounds ? displays.filter((d) => !contains(d.bounds, center(mainBounds))) : [];
  if (notMain.length) return notMain[0];
  return displays.find((d) => d.primary) || displays[0];
}
const center = (b) => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 });
const contains = (b, p) => p.x >= b.x && p.x < b.x + b.width && p.y >= b.y && p.y < b.y + b.height;

/** Fensteroptionen für ein neues Screen-Fenster. */
function windowOptions(mainWin) {
  const d = pickDisplay(listDisplays(), mainWin && !mainWin.isDestroyed() ? mainWin.getBounds() : null, settings.displayId);
  const wa = d ? d.workArea : { x: 80, y: 80, width: 1280, height: 800 };
  const external = d && !d.primary;
  return {
    x: wa.x + (external ? 0 : 60), y: wa.y + (external ? 0 : 40),
    width: external ? wa.width : Math.min(1280, wa.width - 120),
    height: external ? wa.height : Math.min(800, wa.height - 80),
    title: 'Klassentakt – Classroom',
    backgroundColor: '#10221d',
    autoHideMenuBar: true,
  };
}

/** Nach dem Öffnen: Fenster merken, auf Beamer ins Vollbild, wach halten. */
function adopt(child, mainWin) {
  screenWin = child;
  const d = pickDisplay(listDisplays(), mainWin && !mainWin.isDestroyed() ? mainWin.getBounds() : null, settings.displayId);
  if (d && !d.primary && settings.auto) placeOn(d, settings.fullscreen);
  updateKeepAwake();
  child.on('closed', () => { if (screenWin === child) screenWin = null; updateKeepAwake(); onChange(); });
  onChange();
}

function placeOn(display, fullscreen) {
  if (!screenWin || screenWin.isDestroyed() || !display) return;
  const go = () => {
    screenWin.setBounds(display.workArea);
    if (fullscreen) screenWin.setFullScreen(true);
    screenWin.show();
  };
  if (screenWin.isFullScreen()) { screenWin.once('leave-full-screen', go); screenWin.setFullScreen(false); } else go();
}

/** Screen auf einen bestimmten Bildschirm verschieben (und als Wahl merken). */
function moveTo(displayId, { remember = true } = {}) {
  const d = listDisplays().find((x) => x.id === displayId);
  if (!d) return false;
  if (remember) { settings.displayId = d.primary ? null : d.id; save(); }
  placeOn(d, !d.primary && settings.fullscreen);
  onChange();
  return true;
}

/** Screen auf den nächsten Bildschirm schieben (Tastenkürzel). */
function moveNext() {
  if (!screenWin || screenWin.isDestroyed()) return false;
  const ds = listDisplays();
  if (ds.length < 2) return false;
  const cur = screen.getDisplayMatching(screenWin.getBounds());
  const i = ds.findIndex((d) => d.id === cur.id);
  return moveTo(ds[(i + 1) % ds.length].id);
}

function toggleFullscreen() {
  if (!screenWin || screenWin.isDestroyed()) return false;
  screenWin.setFullScreen(!screenWin.isFullScreen());
  return true;
}

function updateKeepAwake() {
  const want = settings.keepAwake && screenWin && !screenWin.isDestroyed();
  if (want && blockerId === null) blockerId = powerSaveBlocker.start('prevent-display-sleep');
  if (!want && blockerId !== null) { powerSaveBlocker.stop(blockerId); blockerId = null; }
}

function setSetting(key, value) {
  if (!(key in DEFAULTS)) return;
  settings[key] = value; save();
  if (key === 'keepAwake') updateKeepAwake();
  onChange();
}

/** Beamer an- oder abgesteckt. */
function wireDisplayEvents() {
  screen.on('display-added', (_e, d) => {
    if (screenWin && !screenWin.isDestroyed() && settings.auto && !d.internal) {
      setTimeout(() => moveTo(d.id, { remember: false }), 800); // macOS braucht einen Moment
    }
    onChange();
  });
  screen.on('display-removed', () => {
    if (screenWin && !screenWin.isDestroyed()) {
      const ds = listDisplays();
      const still = ds.some((d) => contains(d.bounds, center(screenWin.getBounds())));
      if (!still) { const p = ds.find((d) => d.primary) || ds[0]; placeOn(p, false); }
    }
    onChange();
  });
  screen.on('display-metrics-changed', () => onChange());
}

function state() {
  const open = !!(screenWin && !screenWin.isDestroyed());
  return {
    open,
    fullscreen: open && screenWin.isFullScreen(),
    onDisplay: open ? screen.getDisplayMatching(screenWin.getBounds()).id : null,
    awake: blockerId !== null,
    settings: { ...settings },
    displays: listDisplays(),
  };
}

function init(changed) { load(); onChange = changed || (() => {}); wireDisplayEvents(); }

module.exports = {
  init, isScreenRequest, windowOptions, adopt, moveTo, moveNext, toggleFullscreen,
  setSetting, state, listDisplays, pickDisplay,
  get screenWin() { return screenWin; },
};
