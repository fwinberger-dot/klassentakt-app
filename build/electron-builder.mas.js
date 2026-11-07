// Konfiguration für den Mac-App-Store-Build (npm run dist:mas).
// = «build» aus package.json, aber ohne Selbst-Update im Paket (mas.files/mac.files greifen beim Kopieren
// nicht zuverlässig, darum die oberste «files»-Liste) und mit der Store-Version aus package.json «masVersion».
const pkg = require('../package.json');
const base = pkg.build;
const UPDATER = ['!src/updater.js', '!src/update.html', '!src/update-preload.js'];

module.exports = {
  ...base,
  extraMetadata: { version: pkg.masVersion },
  files: [...base.files, ...UPDATER],
  // Datenschutz-Manifest gehört nach Contents/Resources/
  extraResources: [{ from: 'build/PrivacyInfo.xcprivacy', to: 'PrivacyInfo.xcprivacy' }],
};
