// npm test – Mac-App-Store-Build: Sandbox, kein Selbst-Update, gleiche Bundle-ID wie das iPad.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const pkg = require('../package.json');
const mas = require('../build/electron-builder.mas.js');
const has = (plist, key) => new RegExp(`<key>${key.replace(/\./g, '\\.')}</key>\\s*<true/>`).test(plist);

test('gleiche Bundle-ID wie das iPad (Universal Purchase), Store-Version eigen', () => {
  assert.strictEqual(mas.appId, 'ch.klassentakt.app');
  assert.match(read('ios/project.yml'), /PRODUCT_BUNDLE_IDENTIFIER: ch\.klassentakt\.app\n/);
  assert.match(pkg.masVersion, /^\d+\.\d+\.\d+$/);
  assert.strictEqual(mas.extraMetadata.version, pkg.masVersion);
});

test('Selbst-Update ist nicht im Store-Paket und wird dort nicht geladen', () => {
  for (const f of ['!src/updater.js', '!src/update.html', '!src/update-preload.js']) assert.ok(mas.files.includes(f), f);
  assert.match(read('src/main.js'), /const updater = process\.mas \? null : require\('\.\/updater'\);/);
  // jeder Aufruf steht hinter einer Prüfung auf `updater`
  const rest = read('src/main.js')
    .replace(/if \(updater\) \{[\s\S]*?\n  \}/g, '')
    .replace(/if \(updater\) updater\.[^\n]*/g, '')
    .replace(/\.\.\.\(updater \? [^\n]*/g, '');
  assert.doesNotMatch(rest, /updater\.(check|init)\(/);
});

test('Sandbox-Entitlements: nur was die App braucht', () => {
  const e = read(mas.mas.entitlements);
  for (const k of ['com.apple.security.app-sandbox', 'com.apple.security.network.client', 'com.apple.security.device.camera',
    'com.apple.security.device.audio-input', 'com.apple.security.files.user-selected.read-write', 'com.apple.security.print']) assert.ok(has(e, k), k);
  assert.match(e, /Z28KL39TYK\.ch\.klassentakt\.app/);
  for (const k of ['com.apple.security.cs.allow-jit', 'com.apple.security.cs.disable-library-validation', 'com.apple.security.network.server',
    'com.apple.security.files.all']) assert.ok(!e.includes(k), 'nicht: ' + k);
  const i = read(mas.mas.entitlementsInherit);
  assert.ok(has(i, 'com.apple.security.app-sandbox') && has(i, 'com.apple.security.inherit'));
});

test('Info.plist: Export Compliance, Team, Kamera/Mikrofon-Texte; Datenschutz-Manifest', () => {
  assert.strictEqual(mas.mas.extendInfo.ITSAppUsesNonExemptEncryption, false);
  assert.strictEqual(mas.mas.extendInfo.ElectronTeamID, 'Z28KL39TYK');
  assert.ok(mas.mac.extendInfo.NSCameraUsageDescription && mas.mac.extendInfo.NSMicrophoneUsageDescription);
  const r = mas.extraResources.find((x) => x.to === 'PrivacyInfo.xcprivacy');
  assert.ok(r && fs.existsSync(path.join(root, r.from)));
  assert.match(read(r.from), /<key>NSPrivacyTracking<\/key><false\/>/);
});

test('Provisioning-Profil liegt nie im Repo', () => {
  assert.match(read('.gitignore'), /^build\/mas\.provisionprofile$/m);
});
