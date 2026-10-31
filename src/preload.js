// Brücke zwischen der Mac-Hülle und der Web-App klassentakt.ch.
// Die Web-App prüft `window.klassentaktShell` und blendet App-Funktionen nur dann ein.
// Neue Funktionen (Beamer, Webseiten einbetten) kommen hier dazu.
const { contextBridge } = require('electron');

const host = (() => { try { return location.hostname; } catch { return ''; } })();
const trusted = host === 'klassentakt.ch' || host.endsWith('.klassentakt.ch');

if (trusted) {
  contextBridge.exposeInMainWorld('klassentaktShell', Object.freeze({
    isShell: true,
    platform: process.platform,
    shellVersion: '0.1.0',
    features: Object.freeze([]), // z.B. später: ['beamer', 'embed']
  }));
}
