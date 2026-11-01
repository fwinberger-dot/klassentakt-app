// Brücke nur für das Update-Fenster (lokale Datei update.html).
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('ktUpdate', Object.freeze({
  get: () => ipcRenderer.invoke('update:get'),
  choose: (c) => ipcRenderer.invoke('update:choose', String(c)),
  resize: (h) => ipcRenderer.invoke('update:resize', Number(h)),
  onState: (fn) => ipcRenderer.on('update:state', (_e, st) => { try { fn(st); } catch {} }),
}));
