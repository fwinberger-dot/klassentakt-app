// Erzeugt dist/latest.json für das Selbst-Update (läuft in GitHub Actions nach dem Build).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const pkg = require('../package.json');
const v = pkg.version;
const zipName = `Klassentakt-${v}-mac.zip`;
const zip = path.join(__dirname, '..', 'dist', zipName);
const buf = fs.readFileSync(zip);
let notes = '';
try { notes = fs.readFileSync(path.join(__dirname, '..', 'NEU.txt'), 'utf8').trim(); } catch {}
const info = {
  version: v,
  notes,
  url: `https://github.com/fwinberger-dot/klassentakt-app/releases/download/v${v}/${zipName}`,
  sha256: crypto.createHash('sha256').update(buf).digest('hex'),
  size: buf.length,
  date: new Date().toISOString(),
};
fs.writeFileSync(path.join(__dirname, '..', 'dist', 'latest.json'), JSON.stringify(info, null, 2));
console.log(info);
