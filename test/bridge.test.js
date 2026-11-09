// Brücke zur Web-App: Menü «Screen steuern» (⌘⇧S) → onCommand({name:'screen-control'}), nur ans Hauptfenster.
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const read = (f) => fs.readFileSync(path.join(__dirname, '..', f), 'utf8');

test('Screen steuern: Menü, Kürzel, nur bei offenem Screen, nur ans Hauptfenster', () => {
  const main = read('src/main.js');
  assert.match(main, /label: 'Screen steuern', accelerator: 'CmdOrCtrl\+Shift\+S', enabled: s\.open, click: \(\) => shellCommand\('screen-control'\)/);
  assert.match(main, /function shellCommand\(name\) \{\n.*win\.webContents\.send\('shell:command', \{ name \}\)/);
  const accels = [...main.matchAll(/accelerator: '([^']+)'/g)].map((m) => m[1]);
  assert.strictEqual(new Set(accels).size, accels.length, 'Kürzel doppelt: ' + accels);
});

test('Brücke meldet screen-control und bietet onCommand', () => {
  const pre = read('src/preload.js');
  assert.match(pre, /'screen-control',/);
  assert.match(pre, /onCommand: \(fn\) =>/);
  assert.match(pre, /ipcRenderer\.on\('shell:command', h\)/);
});

test('Schwebende Vorschau: Brücke, IPC nur aus der App, Menü', () => {
  const pre = read('src/preload.js');
  assert.match(pre, /'screen-pip-schwebend',/);
  for (const c of ['pip:open', 'pip:close', 'pip:state', 'pip:changed']) assert.ok(pre.includes(`'${c}'`), c);
  const main = read('src/main.js');
  assert.match(main, /ipcMain\.handle\('pip:open', \(e, url\) => \{\n\s+if \(!fromApp\(e\)\) return false;/);
  assert.match(main, /if \(!isApp\(target\)\) return false;/);
  assert.match(main, /Schwebende Vorschau schliessen/);
});

test('pip.pickBounds: Standard unten rechts, gemerkter Ort nur auf vorhandenem Bildschirm', () => {
  // electron wird nur zum Laden benötigt; pickBounds ist reine Rechnung
  const Module = require('module');
  const orig = Module._load;
  Module._load = function (r, ...a) { return r === 'electron' ? { app: {}, screen: {}, BrowserWindow: class {} } : orig.call(this, r, ...a); };
  const { pickBounds, MIN } = require('../src/pip');
  Module._load = orig;
  const d = [{ x: 0, y: 0, width: 1440, height: 900 }];
  const def = pickBounds(null, d);
  assert.deepStrictEqual([def.x + def.width, def.y + def.height], [1440 - 24, 900 - 24]);
  assert.deepStrictEqual(pickBounds({ x: 100, y: 50, width: 600, height: 400 }, d), { x: 100, y: 50, width: 600, height: 400 });
  const weg = pickBounds({ x: 3000, y: 50, width: 600, height: 400 }, d); // Beamer abgesteckt
  assert.strictEqual(weg.width, 600);
  assert.ok(weg.x + weg.width <= 1440);
  assert.strictEqual(pickBounds({ width: 10, height: 10 }, d).width, MIN.width);
});
