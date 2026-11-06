// Welcher Server: immer klassentakt.ch, ausser beim Testen der Download-Version gegen staging:
//   KLASSENTAKT_URL=https://staging.klassentakt.ch/ KT_BASIC=benutzer:passwort open -a Klassentakt
// Nur https und nur *.klassentakt.ch; Basic-Auth nur für genau diesen Server. Im Mac App Store nie.
const DEFAULT = 'https://klassentakt.ch/';

function startUrl(env = process.env, mas = !!process.mas) {
  const v = env.KLASSENTAKT_URL;
  if (mas || !v) return DEFAULT;
  try {
    const u = new URL(v);
    if (u.protocol !== 'https:' || !(u.hostname === 'klassentakt.ch' || u.hostname.endsWith('.klassentakt.ch'))) return DEFAULT;
    return u.origin + '/';
  } catch { return DEFAULT; }
}

/** Zugang für die Basic-Auth von staging, nur wenn genau dieser Server fragt. */
function basicFor(host, env = process.env, mas = !!process.mas) {
  const start = new URL(startUrl(env, mas));
  if (start.href === DEFAULT || host !== start.hostname) return null;
  const b = env.KT_BASIC || '';
  const i = b.indexOf(':');
  return i > 0 ? { username: b.slice(0, i), password: b.slice(i + 1) } : null;
}

module.exports = { DEFAULT, startUrl, basicFor };
