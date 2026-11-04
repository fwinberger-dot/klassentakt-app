// npm test – Update-Quelle (updater.js) und latest.json für /download/ (scripts/latest-json.js).
const test = require('node:test');
const assert = require('node:assert');
const Module = require('module');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

// updater.js braucht electron – für die reinen Funktionen reicht eine Attrappe
const realLoad = Module._load;
Module._load = (req, ...rest) => (req === 'electron' ? { app: {}, net: {}, shell: {}, BrowserWindow: class {}, ipcMain: {} } : realLoad(req, ...rest));
const up = require('../src/updater');
Module._load = realLoad;

const H = 'a'.repeat(64);

test('Update-Quelle ist klassentakt.ch/download/', () => {
  assert.strictEqual(up.LATEST_URL, 'https://klassentakt.ch/download/latest.json');
  assert.strictEqual(up.downloadBase(''), 'https://klassentakt.ch/download/');
});

test('staging per Umgebungsvariable, nur https', () => {
  assert.strictEqual(up.downloadBase('https://staging.klassentakt.ch/download'), 'https://staging.klassentakt.ch/download/');
  assert.strictEqual(up.downloadBase('http://staging.klassentakt.ch/download/'), 'https://klassentakt.ch/download/');
  assert.strictEqual(up.downloadBase('kaputt'), 'https://klassentakt.ch/download/');
});

test('latest.json: relative URL wird absolut', () => {
  const i = up.parseLatest({ version: '0.4.1', url: 'Klassentakt-mac.zip', sha256: H });
  assert.strictEqual(i.url, 'https://klassentakt.ch/download/Klassentakt-mac.zip');
  const s = up.parseLatest({ version: '0.4.1', url: 'Klassentakt-mac.zip', sha256: H }, 'https://staging.klassentakt.ch/download/');
  assert.strictEqual(s.url, 'https://staging.klassentakt.ch/download/Klassentakt-mac.zip');
});

test('latest.json: fremde Server, falsche Dateien, fehlende Prüfsumme abgelehnt', () => {
  assert.throws(() => up.parseLatest({ version: '0.4.1', url: 'https://example.com/Klassentakt-mac.zip', sha256: H }), /Download-Adresse/);
  assert.throws(() => up.parseLatest({ version: '0.4.1', url: '//example.com/x.zip', sha256: H }), /Download-Adresse/);
  assert.throws(() => up.parseLatest({ version: '0.4.1', url: 'Klassentakt-mac.dmg', sha256: H }), /Download-Adresse/);
  assert.throws(() => up.parseLatest({ version: '0.4.1', url: 'Klassentakt-mac.zip', sha256: 'abc' }), /unvollständig/);
  assert.throws(() => up.parseLatest({ version: '1.0', url: 'Klassentakt-mac.zip', sha256: H }), /Version/);
});

test('Versionen vergleichen', () => {
  assert.ok(up.newer('0.4.1', '0.4.0'));
  assert.ok(!up.newer('0.4.0', '0.4.1'));
  assert.ok(up.newer('0.10.0', '0.9.9'));
});

test('dist/download/: Dateien und latest.json passen zu ops/download.sh', () => {
  const v = require('../package.json').version;
  const dist = fs.mkdtempSync(path.join(os.tmpdir(), 'kt-dist-'));
  fs.writeFileSync(path.join(dist, `Klassentakt-${v}-mac.zip`), 'zip-inhalt');
  fs.writeFileSync(path.join(dist, `Klassentakt-${v}.dmg`), 'dmg-inhalt');
  execFileSync(process.execPath, [path.join(__dirname, '..', 'scripts', 'latest-json.js')], { env: { ...process.env, KT_DIST: dist }, stdio: 'ignore' });
  const dl = path.join(dist, 'download');
  assert.deepStrictEqual(fs.readdirSync(dl).sort(), ['Klassentakt-mac.dmg', 'Klassentakt-mac.zip', 'latest.json']);
  const j = JSON.parse(fs.readFileSync(path.join(dl, 'latest.json'), 'utf8'));
  const sha = (f, a, enc) => crypto.createHash(a).update(fs.readFileSync(path.join(dl, f))).digest(enc);
  assert.strictEqual(j.version, v);
  assert.strictEqual(j.url, 'Klassentakt-mac.zip');
  assert.strictEqual(j.sha256, sha('Klassentakt-mac.zip', 'sha256', 'hex'));
  assert.strictEqual(j.sha512, sha('Klassentakt-mac.zip', 'sha512', 'base64'));
  assert.strictEqual(j.dmg.url, 'Klassentakt-mac.dmg');
  assert.strictEqual(j.dmg.sha256, sha('Klassentakt-mac.dmg', 'sha256', 'hex'));
  // die App nimmt sie an
  assert.strictEqual(up.parseLatest(j).url, 'https://klassentakt.ch/download/Klassentakt-mac.zip');
  // gleicher jq-Filter wie sha_json() in ops/download.sh: genau ein Hash pro Datei
  let jq = true; try { execFileSync('jq', ['--version'], { stdio: 'ignore' }); } catch { jq = false; }
  if (jq) {
    for (const f of ['Klassentakt-mac.dmg', 'Klassentakt-mac.zip']) {
      const out = execFileSync('jq', ['-r', '--arg', 'f', f, '[.. | objects | select(any(.[]; type == "string" and endswith($f))) | (.sha256 // .sha256sum // .SHA256 // empty) | ascii_downcase] | unique | .[]', path.join(dl, 'latest.json')], { encoding: 'utf8' }).trim();
      assert.strictEqual(out, sha(f, 'sha256', 'hex'), f);
    }
  }
  // GitHub-latest.json für alte Apps (bis 0.4.0) bleibt
  const gh = JSON.parse(fs.readFileSync(path.join(dist, 'latest.json'), 'utf8'));
  assert.match(gh.url, /^https:\/\/github\.com\//);
  fs.rmSync(dist, { recursive: true, force: true });
});
