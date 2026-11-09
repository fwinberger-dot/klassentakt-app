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

test('Schwebende Vorschau: ktfloat-Fenster, Brücke, Menü', () => {
  const pre = read('src/preload.js');
  assert.match(pre, /'float-preview',/);
  assert.match(pre, /send: \(name, payload\) => \{ if \(name === 'float-preview'\)/);
  const main = read('src/main.js');
  assert.match(main, /\(isApp\(url\) \|\| blank\) && pip\.isPipRequest\(frameName\)/);
  assert.match(main, /else if \(pip\.isPipRequest\(details\.frameName\)\) pip\.adopt\(child\)/);
  assert.match(main, /Schwebende Vorschau schliessen/);
});

test('pip: Grösse aus window.open-Features, Mindestgrösse, Ort nur auf vorhandenem Bildschirm', () => {
  const Module = require('module');
  const orig = Module._load;
  Module._load = function (r, ...a) { return r === 'electron' ? { app: {}, screen: {} } : orig.call(this, r, ...a); };
  const { sizeFrom, pickPosition, isPipRequest } = require('../src/pip');
  Module._load = orig;
  assert.ok(isPipRequest('ktfloat') && !isPipRequest('wp_classroom') && !isPipRequest(''));
  assert.deepStrictEqual(sizeFrom('popup=yes,width=600,height=400'), { width: 600, height: 400 });
  assert.deepStrictEqual(sizeFrom(''), { width: 480, height: 353 });
  assert.deepStrictEqual(sizeFrom('width=10,height=10'), { width: 260, height: 200 });
  const a = [{ x: 0, y: 0, width: 1440, height: 900 }];
  const s = { width: 480, height: 353 };
  assert.deepStrictEqual(pickPosition(null, s, a), { x: 1440 - 480 - 24, y: 900 - 353 - 24 });
  assert.deepStrictEqual(pickPosition({ x: 100, y: 50 }, s, a), { x: 100, y: 50 });
  assert.deepStrictEqual(pickPosition({ x: 3000, y: 50 }, s, a), { x: 1440 - 480 - 24, y: 900 - 353 - 24 }); // Beamer abgesteckt
});
