// Erzeugt die Dateien für das Selbst-Update (läuft in GitHub Actions nach dem Build).
// Update-Fenster zeigt standardmässig KEINEN Text. Nur wenn NEU.txt mit «Version <diese Version>»
// beginnt, werden die Zeilen darunter als «Was ist neu» angezeigt (z.B. um eine Funktion anzupreisen).
// So erscheint nie ein alter Text bei einer neuen Version.
//
// dist/download/  → für https://klassentakt.ch/download/ (hochladen mit ops/download.sh im Web-Repo):
//   Klassentakt-mac.dmg, Klassentakt-mac.zip, latest.json (URLs relativ zu /download/)
// dist/latest.json → GitHub-Release, nur noch für Apps bis 0.4.0 (lesen latest.json von GitHub)
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const pkg = require('../package.json');
const v = pkg.version;
const root = path.join(__dirname, '..');
const dist = process.env.KT_DIST || path.join(root, 'dist'); // KT_DIST nur für Tests
const zipName = `Klassentakt-${v}-mac.zip`;
const dmgName = `Klassentakt-${v}.dmg`;

const describe = (file, name) => {
  const buf = fs.readFileSync(file);
  return {
    url: name,
    sha256: crypto.createHash('sha256').update(buf).digest('hex'),
    sha512: crypto.createHash('sha512').update(buf).digest('base64'),
    size: buf.length,
  };
};

let notes = '';
try {
  const lines = fs.readFileSync(path.join(root, 'NEU.txt'), 'utf8').split('\n');
  if (lines[0].trim() === `Version ${v}`) notes = lines.slice(1).join('\n').trim();
} catch {}
const date = new Date().toISOString();

// /download/
const dl = path.join(dist, 'download');
fs.mkdirSync(dl, { recursive: true });
fs.copyFileSync(path.join(dist, zipName), path.join(dl, 'Klassentakt-mac.zip'));
fs.copyFileSync(path.join(dist, dmgName), path.join(dl, 'Klassentakt-mac.dmg'));
const zip = describe(path.join(dl, 'Klassentakt-mac.zip'), 'Klassentakt-mac.zip');
const latest = {
  version: v,
  notes,
  ...zip, // url, sha256, sha512, size: das Update-zip (liest updater.js)
  dmg: describe(path.join(dl, 'Klassentakt-mac.dmg'), 'Klassentakt-mac.dmg'),
  date,
};
fs.writeFileSync(path.join(dl, 'latest.json'), JSON.stringify(latest, null, 2) + '\n');

// GitHub-Release (alte Apps)
const gh = {
  version: v,
  notes,
  url: `https://github.com/fwinberger-dot/klassentakt-app/releases/download/v${v}/${zipName}`,
  sha256: zip.sha256,
  size: zip.size,
  date,
};
fs.writeFileSync(path.join(dist, 'latest.json'), JSON.stringify(gh, null, 2));
fs.writeFileSync(path.join(dist, 'release-notes.md'), notes || `Klassentakt ${v}`);
console.log(latest);
