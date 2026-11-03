// Erzeugt dist/latest.json für das Selbst-Update (läuft in GitHub Actions nach dem Build).
// Update-Fenster zeigt standardmässig KEINEN Text. Nur wenn NEU.txt mit «Version <diese Version>»
// beginnt, werden die Zeilen darunter als «Was ist neu» angezeigt (z.B. um eine Funktion anzupreisen).
// So erscheint nie ein alter Text bei einer neuen Version.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const pkg = require('../package.json');
const v = pkg.version;
const root = path.join(__dirname, '..');
const zipName = `Klassentakt-${v}-mac.zip`;
const buf = fs.readFileSync(path.join(root, 'dist', zipName));

let notes = '';
try {
  const lines = fs.readFileSync(path.join(root, 'NEU.txt'), 'utf8').split('\n');
  if (lines[0].trim() === `Version ${v}`) notes = lines.slice(1).join('\n').trim();
} catch {}

const info = {
  version: v,
  notes,
  url: `https://github.com/fwinberger-dot/klassentakt-app/releases/download/v${v}/${zipName}`,
  sha256: crypto.createHash('sha256').update(buf).digest('hex'),
  size: buf.length,
  date: new Date().toISOString(),
};
fs.writeFileSync(path.join(root, 'dist', 'latest.json'), JSON.stringify(info, null, 2));
fs.writeFileSync(path.join(root, 'dist', 'release-notes.md'), notes || `Klassentakt ${v}`);
console.log(info);
