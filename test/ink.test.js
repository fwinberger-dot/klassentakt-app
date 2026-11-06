// Handschrift-Brücke: Aufträge prüfen, Antworten säubern, kt-ink auf dem Mac wirklich erkennen lassen.
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const { validate, clean, differs, createInk, LIMITS } = require('../src/ink');
const { strokesFor } = require('./fixtures/ink-strokes');

const job = (o = {}) => ({ id: 'a1', lang: 'de-CH', width: 800, height: 120, strokes: strokesFor('HEFT'), png: '', ...o });

test('gültiger Auftrag wird auf x/y gekürzt', () => {
  const v = validate(job());
  assert.ok(v);
  assert.strictEqual(v.id, 'a1');
  assert.deepStrictEqual(Object.keys(v).sort(), ['height', 'id', 'png', 'strokes', 'width']);
  assert.strictEqual(v.strokes[0].points[0].length, 2);
});

test('ungültige Aufträge werden abgelehnt', () => {
  assert.strictEqual(validate(null), null);
  assert.strictEqual(validate(job({ id: { x: 1 } })), null);
  assert.strictEqual(validate(job({ width: -1 })), null);
  assert.strictEqual(validate(job({ width: LIMITS.size + 1 })), null);
  assert.strictEqual(validate(job({ strokes: 'x' })), null);
  assert.strictEqual(validate(job({ strokes: [{ points: [['a', 1]] }] })), null);
  assert.strictEqual(validate(job({ strokes: [{ points: [[Infinity, 1]] }] })), null);
  assert.strictEqual(validate(job({ strokes: Array.from({ length: LIMITS.strokes + 1 }, () => ({ points: [[1, 1]] })) })), null);
  assert.strictEqual(validate(job({ strokes: [{ points: Array.from({ length: LIMITS.points + 1 }, () => [1, 1]) }] })), null);
  assert.strictEqual(validate(job({ strokes: [] })), null, 'weder Striche noch Bild');
  assert.strictEqual(validate(job({ strokes: [], png: 'data:text/html;base64,AAAA' })), null, 'nur PNG erlaubt');
  assert.ok(validate(job({ strokes: [], png: 'data:image/png;base64,AAAA' })), 'nur PNG geht');
});

test('Antwort wird auf den Vertrag gekürzt', () => {
  assert.deepStrictEqual(clean({ text: 'Heft', alternatives: ['Heft', 'Hef', 3, 'Hefte', 'Heff', 'x'], confidence: 1.5, extra: 1 }),
    { text: 'Heft', alternatives: ['Hef', 'Hefte', 'Heff'], confidence: 1 });
  assert.deepStrictEqual(clean({ error: 'keine Striche' }), { error: 'keine Striche' });
  assert.deepStrictEqual(clean('x'), { error: 'Erkennung fehlgeschlagen' });
});

test('stark abweichende Vorschläge senken die Sicherheit', () => {
  assert.strictEqual(differs('HEFT HOLEN', 'HEFTHOLEN'), false);
  assert.strictEqual(differs('Lies den Text auf Seite 12', 'Les der Text alf Seite 12'), true);
  // nur Leerzeichen bzw. ein Buchstabe anders → bleibt sicher
  assert.strictEqual(clean({ text: 'HEFT HOLEN', alternatives: ['HEFTHOLEN', 'HET HOLEN'], confidence: 1 }).confidence, 1);
  // ganz anderer Vorschlag → unsicher (< 0.7)
  assert.strictEqual(clean({ text: 'Hef hotor und Datum schreiben', alternatives: ['Heft holen und Datum schreiben'], confidence: 1 }).confidence, 0.5);
  assert.strictEqual(clean({ text: 'Lies', alternatives: ['Lisa', 'Lesen'], confidence: 0.3 }).confidence, 0.3, 'nie erhöhen');
});

test('ohne kt-ink: Fehler statt Hängen, Feature fehlt', () => {
  const ink = createInk('/gibt/es/nicht/kt-ink');
  assert.strictEqual(ink.available(), false);
  let r; ink.recognize(job(), (x) => { r = x; });
  assert.deepStrictEqual(r, { id: 'a1', error: 'Erkennung nicht vorhanden' });
  ink.recognize({ id: 'b' }, (x) => { r = x; });
  assert.deepStrictEqual(r, { id: 'b', error: 'Ungültiger Auftrag' });
});

const bin = path.join(__dirname, '..', 'native', 'bin', 'kt-ink');
test('kt-ink erkennt Blockschrift (macOS, nach npm run build:ink)', { skip: process.platform !== 'darwin' || !fs.existsSync(bin) }, async () => {
  const ink = createInk(bin);
  const ask = (p) => new Promise((res) => ink.recognize(p, res));
  try {
    const [a, b] = await Promise.all([ask(job({ id: 'x', strokes: strokesFor('HEFT HOLEN') })), ask(job({ id: 'y', strokes: strokesFor('LOTTE') }))]);
    assert.strictEqual(a.id, 'x');
    assert.match(a.text, /HEFT ?HOLEN/i);
    assert.ok(Array.isArray(a.alternatives));
    assert.ok(a.confidence >= 0 && a.confidence <= 1);
    assert.strictEqual(b.id, 'y');
    assert.match(b.text, /LOTTE/i);
  } finally { ink.stop(); }
});
