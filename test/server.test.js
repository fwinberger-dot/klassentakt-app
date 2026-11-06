// Server-Wahl: klassentakt.ch, zum Testen staging; Basic-Auth nur dorthin, im Store nie.
const { test } = require('node:test');
const assert = require('node:assert');
const { DEFAULT, startUrl, basicFor } = require('../src/server');

const ST = { KLASSENTAKT_URL: 'https://staging.klassentakt.ch/egal?x=1', KT_BASIC: 'lehrer:geheim:mit:doppelpunkt' };

test('Standard ist klassentakt.ch', () => {
  assert.strictEqual(startUrl({}, false), DEFAULT);
  assert.strictEqual(startUrl(ST, false), 'https://staging.klassentakt.ch/');
});

test('nur https und nur *.klassentakt.ch; im Mac App Store nie', () => {
  for (const v of ['http://staging.klassentakt.ch/', 'https://klassentakt.ch.boese.ch/', 'https://boese.ch/', 'kaputt'])
    assert.strictEqual(startUrl({ KLASSENTAKT_URL: v }, false), DEFAULT, v);
  assert.strictEqual(startUrl(ST, true), DEFAULT);
});

test('Basic-Auth nur für genau den Testserver', () => {
  assert.deepStrictEqual(basicFor('staging.klassentakt.ch', ST, false), { username: 'lehrer', password: 'geheim:mit:doppelpunkt' });
  assert.strictEqual(basicFor('klassentakt.ch', ST, false), null);
  assert.strictEqual(basicFor('boese.ch', ST, false), null);
  assert.strictEqual(basicFor('staging.klassentakt.ch', ST, true), null, 'Store');
  assert.strictEqual(basicFor('klassentakt.ch', { KT_BASIC: 'a:b' }, false), null, 'ohne Testserver nie');
  assert.strictEqual(basicFor('staging.klassentakt.ch', { KLASSENTAKT_URL: ST.KLASSENTAKT_URL, KT_BASIC: 'ohne' }, false), null);
});
