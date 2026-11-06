// Handschrift → Text (Brücke `recognize-ink` → `ink-text`, siehe docs/Handschrift.md der Web-App).
// Erkannt wird mit macOS Vision im Hilfsprogramm kt-ink (native/ink/main.swift), auf dem Gerät, ohne Netz.
// kt-ink startet erst bei der ersten Erkennung und endet nach 5 Minuten ohne Auftrag.
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const LIMITS = { strokes: 500, points: 50000, png: 4 * 1024 * 1024, size: 10000, text: 2000 };
const TIMEOUT_MS = 7000; // die Web-App wartet 8 s, danach nimmt sie Tesseract
const IDLE_MS = 5 * 60 * 1000;

const num = (v) => typeof v === 'number' && Number.isFinite(v);

/** Auftrag der Web-App prüfen und auf das Nötige kürzen. Gibt null zurück, wenn er nicht passt. */
function validate(p) {
  if (!p || typeof p !== 'object') return null;
  const id = p.id;
  if (!((typeof id === 'string' && id.length <= 64) || num(id))) return null;
  const width = p.width, height = p.height;
  if (!num(width) || !num(height) || width <= 0 || height <= 0 || width > LIMITS.size || height > LIMITS.size) return null;
  if (!Array.isArray(p.strokes) || p.strokes.length > LIMITS.strokes) return null;
  let total = 0;
  const strokes = [];
  for (const s of p.strokes) {
    if (!s || !Array.isArray(s.points)) return null;
    total += s.points.length;
    if (total > LIMITS.points) return null;
    const points = [];
    for (const q of s.points) {
      if (!Array.isArray(q) || q.length < 2 || !num(q[0]) || !num(q[1])) return null;
      points.push([q[0], q[1]]);
    }
    if (points.length) strokes.push({ points });
  }
  let png = '';
  if (typeof p.png === 'string' && p.png.length <= LIMITS.png && p.png.startsWith('data:image/png;base64,')) png = p.png;
  if (!strokes.length && !png) return null;
  return { id, width, height, strokes, png };
}

const norm = (t) => t.toLowerCase().replace(/\s+/g, '');
function distance(a, b) {
  let d = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const n = [i];
    for (let j = 1; j <= b.length; j++) n[j] = Math.min(d[j] + 1, n[j - 1] + 1, d[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    d = n;
  }
  return d[b.length];
}
/** Weicht der Vorschlag stark ab? Ab 3 verschiedenen Zeichen oder einem Viertel (ohne Leerzeichen, Gross/klein). */
const differs = (text, alt) => { const a = norm(text), b = norm(alt), d = distance(a, b); return d >= 3 || d / Math.max(a.length, b.length, 1) > 0.25; };
// Vision meldet oft 1.0, auch wenn es falsch liegt. Weicht ein Vorschlag stark ab, ist es unsicher
// (die Web-App markiert unter 0.7 «Unsicher erkannt»).
const UNSURE_CONF = 0.5;

/** Antwort von kt-ink in die Form des Vertrags bringen. */
function clean(r) {
  if (!r || typeof r !== 'object') return { error: 'Erkennung fehlgeschlagen' };
  if (r.error) return { error: String(r.error).slice(0, 200) };
  const text = typeof r.text === 'string' ? r.text.slice(0, LIMITS.text) : '';
  const alternatives = (Array.isArray(r.alternatives) ? r.alternatives : [])
    .filter((a) => typeof a === 'string' && a && a !== text).slice(0, 3).map((a) => a.slice(0, LIMITS.text));
  const out = { text, alternatives };
  if (num(r.confidence)) out.confidence = Math.min(1, Math.max(0, r.confidence));
  if (text && alternatives.some((a) => differs(text, a))) out.confidence = Math.min(out.confidence ?? 1, UNSURE_CONF);
  return out;
}

/** Pfad zu kt-ink: in der fertigen App unter Contents/Resources, beim Entwickeln in native/bin/. */
function binPath(electronApp) {
  if (electronApp && electronApp.isPackaged) return path.join(process.resourcesPath, 'kt-ink');
  return path.join(__dirname, '..', 'native', 'bin', 'kt-ink');
}

function createInk(bin) {
  let proc = null, buf = '', seq = 0, idle = null;
  const pending = new Map(); // seq → { id, reply, timer }

  const available = () => process.platform === 'darwin' && fs.existsSync(bin);

  function settle(key, result) {
    const job = pending.get(key);
    if (!job) return;
    pending.delete(key);
    clearTimeout(job.timer);
    job.reply({ id: job.id, ...result });
  }

  function stop() {
    clearTimeout(idle); idle = null;
    if (proc) { try { proc.kill(); } catch {} proc = null; }
    for (const key of [...pending.keys()]) settle(key, { error: 'Erkennung beendet' });
  }

  function start() {
    proc = spawn(bin, [], { stdio: ['pipe', 'pipe', 'ignore'] });
    buf = '';
    const me = proc;
    proc.stdout.setEncoding('utf8');
    proc.stdout.on('data', (chunk) => {
      buf += chunk;
      let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl); buf = buf.slice(nl + 1);
        let r; try { r = JSON.parse(line); } catch { continue; }
        settle(r.id, clean(r));
      }
    });
    const gone = () => { if (proc === me) { proc = null; for (const key of [...pending.keys()]) settle(key, { error: 'Erkennung abgebrochen' }); } };
    proc.on('exit', gone);
    proc.on('error', gone);
    proc.stdin.on('error', () => {});
  }

  /** Auftrag erkennen; `reply` bekommt genau einmal {id, text, alternatives, confidence} oder {id, error}. */
  function recognize(payload, reply) {
    const job = validate(payload);
    if (!job) { reply({ id: payload && payload.id, error: 'Ungültiger Auftrag' }); return; }
    if (!available()) { reply({ id: job.id, error: 'Erkennung nicht vorhanden' }); return; }
    if (!proc) start();
    const key = ++seq;
    pending.set(key, { id: job.id, reply, timer: setTimeout(() => settle(key, { error: 'Zeitüberschreitung' }), TIMEOUT_MS) });
    proc.stdin.write(JSON.stringify({ ...job, id: key }) + '\n');
    clearTimeout(idle);
    idle = setTimeout(stop, IDLE_MS);
  }

  return { available, recognize, stop };
}

module.exports = { validate, clean, differs, binPath, createInk, LIMITS };
