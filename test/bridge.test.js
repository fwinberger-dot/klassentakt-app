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
