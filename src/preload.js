// Brücke zwischen der Mac-Hülle und der Web-App klassentakt.ch.
// Die Web-App prüft `window.klassentaktShell` und blendet App-Funktionen nur dann ein.
const { contextBridge, ipcRenderer } = require('electron');

const host = (() => { try { return location.hostname; } catch { return ''; } })();
const trusted = host === 'klassentakt.ch' || host.endsWith('.klassentakt.ch');

if (trusted) {
  contextBridge.exposeInMainWorld('klassentaktShell', Object.freeze({
    isShell: true,
    platform: process.platform,
    shellVersion: '0.3.0',
    features: Object.freeze(['beamer', 'update']),
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
