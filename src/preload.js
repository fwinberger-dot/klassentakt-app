// Brücke zwischen der Mac-Hülle und der Web-App klassentakt.ch.
// Die Web-App prüft `window.klassentaktShell` und blendet App-Funktionen nur dann ein.
const { contextBridge, ipcRenderer } = require('electron');

const host = (() => { try { return location.hostname; } catch { return ''; } })();
const trusted = host === 'klassentakt.ch' || host.endsWith('.klassentakt.ch');

if (trusted) {
  contextBridge.exposeInMainWorld('klassentaktShell', Object.freeze({
    isShell: true,
    platform: process.platform,
    shellVersion: (process.argv.find((a) => a.startsWith('--kt-shell-version=')) || '=0.4.1').split('=')[1],
    store: !!process.mas, // Mac App Store: Updates über Apple
    features: Object.freeze([
      'beamer',
      'screen-pip-schwebend', // pip.open/close/state/onChange: schwebendes Vorschau-Fenster
      'screen-control', // Menü «Screen steuern» (⌘⇧S) → onCommand({name:'screen-control'})
      ...(process.mas ? [] : ['update']),
    ]),
    onCommand: (fn) => {
      if (typeof fn !== 'function') return () => {};
      const h = (_e, cmd) => { try { fn(cmd); } catch {} };
      ipcRenderer.on('shell:command', h);
      return () => ipcRenderer.removeListener('shell:command', h);
    },
    pip: Object.freeze({
      // open(url) → bool (url: Vorschau-Seite auf klassentakt.ch, relativ oder absolut); close() → bool
      open: (url) => ipcRenderer.invoke('pip:open', String(url || '')),
      close: () => ipcRenderer.invoke('pip:close'),
      state: () => ipcRenderer.invoke('pip:state'), // { open, bounds:{x,y,width,height}|null }
      onChange: (fn) => { // feuert beim Öffnen und beim Schliessen (auch wenn der Benutzer das Fenster schliesst)
        if (typeof fn !== 'function') return () => {};
        const h = (_e, st) => { try { fn(st); } catch {} };
        ipcRenderer.on('pip:changed', h);
        return () => ipcRenderer.removeListener('pip:changed', h);
      },
    }),
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
