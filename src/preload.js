// Brücke zwischen der Mac-Hülle und der Web-App klassentakt.ch.
// Die Web-App prüft `window.klassentaktShell` und blendet App-Funktionen nur dann ein.
const { contextBridge, ipcRenderer } = require('electron');

const host = (() => { try { return location.hostname; } catch { return ''; } })();
const trusted = host === 'klassentakt.ch' || host.endsWith('.klassentakt.ch');
const ink = process.argv.includes('--kt-ink'); // Handschrift-Erkennung (kt-ink) vorhanden
// Nachrichten wie in der iPad-App (send/on); die Mac-App kennt bisher nur recognize-ink → ink-text.
const SEND = ['recognize-ink'];
const EVENTS = ['ink-text'];

if (trusted) {
  contextBridge.exposeInMainWorld('klassentaktShell', Object.freeze({
    isShell: true,
    platform: process.platform,
    shellVersion: (process.argv.find((a) => a.startsWith('--kt-shell-version=')) || '=0.4.1').split('=')[1],
    store: !!process.mas, // Mac App Store: Updates über Apple
    features: Object.freeze([
      'beamer',
      ...(process.mas ? [] : ['update']),
      ...(ink ? ['ink-text'] : []),
    ]),
    send: (name, payload) => { if (SEND.includes(name)) ipcRenderer.send('shell:send', name, payload); },
    on: (name, fn) => {
      if (!EVENTS.includes(name) || typeof fn !== 'function') return () => {};
      const h = (_e, n, p) => { if (n === name) { try { fn(p); } catch {} } };
      ipcRenderer.on('shell:event', h);
      return () => ipcRenderer.removeListener('shell:event', h);
    },
    beamer: Object.freeze({
      // { open, fullscreen, onDisplay, awake, settings, displays:[{id,label,primary,internal}] }
      state: () => ipcRenderer.invoke('beamer:state'),
      moveTo: (displayId) => ipcRenderer.invoke('beamer:moveTo', displayId),
      next: () => ipcRenderer.invoke('beamer:next'),
      toggleFullscreen: () => ipcRenderer.invoke('beamer:fullscreen'),
      onChange: (fn) => {
        if (typeof fn !== 'function') return () => {};
        const h = (_e, st) => { try { fn(st); } catch {} };
        ipcRenderer.on('beamer:changed', h);
        return () => ipcRenderer.removeListener('beamer:changed', h);
      },
    }),
  }));
}
