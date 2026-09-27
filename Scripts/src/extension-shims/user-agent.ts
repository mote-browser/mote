// WebKit gives a worker the user agent of the last web page that set
// one — Safari's, as Mote's tabs send — not the Chrome one the
// extension's pages have. Code that picks its path by it then takes
// the Safari one: Bitwarden's asks a Safari app for a reply thousands
// of times a second and floods the browser.
// Its pages too: an extension reads navigator.userAgent to pick a code
// path, a download, a welcome page, and finds nothing it knows in
// Safari's. (Not WebKit's setting: see Extensions.init.)

import type { Shim } from './types';

/** Safari's user agent made Chrome's `version`. */
export function chromeUserAgent(userAgent: string, version: string): string {
  return (
    userAgent.replace(/ Version\/[\d.]+.*$/, '').replace(/ Safari\/[\d.]+$/, '') +
    ' Chrome/' +
    version +
    ' Safari/537.36'
  );
}

interface Brand {
  brand: string;
  version: string;
}

/** Chrome's `navigator.userAgentData` for a Chrome user agent. */
export function userAgentData(chromeUA: string, version: string) {
  const major = version.split('.')[0]!;
  const brands: Brand[] = [
    { brand: 'Chromium', version: major },
    { brand: 'Google Chrome', version: major },
    { brand: 'Not.A/Brand', version: '99' },
  ];
  const low = { brands, mobile: false, platform: 'macOS' };
  const mac =
    (chromeUA.match(/Mac OS X (\d+)[_.](\d+)(?:[_.](\d+))?/) || [])
      .slice(1)
      .map((n) => n || '0')
      .join('.') || '10.15.7';
  const high: Record<string, unknown> = {
    architecture: 'arm',
    bitness: '64',
    model: '',
    platformVersion: mac,
    wow64: false,
    fullVersionList: brands.map((b) => ({
      brand: b.brand,
      version: b.version === major ? version : b.version + '.0.0.0',
    })),
    uaFullVersion: version,
  };
  const pick = (hints: unknown) =>
    Object.assign(
      {},
      low,
      ...(Array.isArray(hints) ? hints : []).filter((h) => h in high).map((h) => ({ [h]: high[h] })),
    );
  return Object.assign({}, low, {
    getHighEntropyValues: (hints: unknown) => Promise.resolve(pick(hints)),
    toJSON: () => low,
  });
}

export function presentAsChrome({ root, inContent, worker, config }: Shim): void {
  if (inContent || typeof navigator === 'undefined' || / Chrome\//.test(navigator.userAgent)) return;
  const chromeUA = chromeUserAgent(navigator.userAgent, config.chromeVersion);
  const proto =
    typeof root.WorkerNavigator !== 'undefined' && worker
      ? root.WorkerNavigator.prototype
      : typeof Navigator !== 'undefined'
        ? Navigator.prototype
        : null;
  try {
    if (proto) {
      Object.defineProperty(proto, 'userAgent', { get: () => chromeUA, configurable: true });
      Object.defineProperty(proto, 'appVersion', {
        get: () => chromeUA.replace(/^Mozilla\//, ''),
        configurable: true,
      });
      Object.defineProperty(proto, 'vendor', { get: () => 'Google Inc.', configurable: true });
      if (!('userAgentData' in navigator)) {
        const data = userAgentData(chromeUA, config.chromeVersion);
        Object.defineProperty(proto, 'userAgentData', { get: () => data, configurable: true });
      }
    }
  } catch {}
}
