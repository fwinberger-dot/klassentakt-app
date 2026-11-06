// Erfundene Striche in Blockbuchstaben, wie sie die Web-App schickt ([x, y, t, druck] in CSS-Pixeln).
const L = {
  H: [[[0, 0], [0, 1]], [[0.6, 0], [0.6, 1]], [[0, 0.5], [0.6, 0.5]]],
  E: [[[0.6, 0], [0, 0], [0, 1], [0.6, 1]], [[0, 0.5], [0.5, 0.5]]],
  F: [[[0.6, 0], [0, 0], [0, 1]], [[0, 0.5], [0.5, 0.5]]],
  T: [[[0, 0], [0.7, 0]], [[0.35, 0], [0.35, 1]]],
  O: [[[0.3, 0], [0.6, 0.2], [0.6, 0.8], [0.3, 1], [0, 0.8], [0, 0.2], [0.3, 0]]],
  L: [[[0, 0], [0, 1], [0.6, 1]]],
  N: [[[0, 1], [0, 0], [0.6, 1], [0.6, 0]]],
};
/** Wort → Striche, mit leichtem Wackeln und Zwischenpunkten. */
function strokesFor(word, size = 60) {
  let x = 20, t = 0, seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647 - 0.5);
  const strokes = [];
  for (const ch of word) {
    if (ch === ' ') { x += size * 0.6; continue; }
    for (const seg of L[ch]) {
      const points = [];
      for (let i = 0; i < seg.length - 1; i++) {
        for (let k = 0; k < 8; k++) {
          const f = k / 8, a = seg[i], b = seg[i + 1];
          points.push([x + (a[0] + (b[0] - a[0]) * f) * size + rnd() * 2, 20 + (a[1] + (b[1] - a[1]) * f) * size + rnd() * 2, (t += 8), 0.5]);
        }
      }
      const e = seg[seg.length - 1];
      points.push([x + e[0] * size, 20 + e[1] * size, (t += 8), 0.5]);
      strokes.push({ type: 'pen', points });
    }
    x += size * 0.9;
  }
  return strokes;
}
module.exports = { strokesFor };
