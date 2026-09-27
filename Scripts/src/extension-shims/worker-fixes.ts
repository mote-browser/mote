// Where an extension's service worker in WebKit behaves unlike Chrome's.

import { DOMException, URL } from './captured';
import type { Shim } from './types';

/**
 * The static routing API of Chrome's service workers (install
 * event.addRoutes) — a speed-up, so nothing is lost without it.
 */
export function addInstallRoutes({ root, worker }: Shim): void {
  if (worker && typeof root.InstallEvent === 'function' && !root.InstallEvent.prototype.addRoutes) {
    root.InstallEvent.prototype.addRoutes = () => Promise.resolve();
  }
}

/** The scripts an extension ships, by path, from `ShimConfig.scripts`. */
export interface ShippedScripts {
  shipped: Set<string>;
  empty: Set<string>;
}

export function shippedScripts(scripts: readonly string[]): ShippedScripts {
  const shipped = new Set<string>();
  const empty = new Set<string>();
  for (const path of scripts) {
    if (path.startsWith('-')) empty.add(path.slice(1));
    else shipped.add(path);
  }
  return { shipped, empty };
}

/** What `importScripts` does with a script: load it, skip it (empty), or refuse it (not shipped). */
export type ImportVerdict = 'load' | 'skip' | 'missing';

export function importVerdict(
  url: { origin: string; pathname: string },
  origin: string,
  files: ShippedScripts,
): ImportVerdict {
  const path = decodeURIComponent(url.pathname);
  if (url.origin === origin && files.empty.has(path)) return 'skip';
  if (url.origin === origin && !files.shipped.has(path)) return 'missing';
  return 'load';
}

/**
 * A script a worker imports that isn't there: Chrome throws at once.
 * WebKit goes looking for it first, and while it does, runs the
 * promises already waiting — code that notes "still starting" until
 * its first promise settles (Tampermonkey) then thinks startup is
 * over, and refuses its own listeners. The extension's files are
 * known, so a missing one is refused the way Chrome refuses it, and
 * an empty one — Tampermonkey's test.js — isn't fetched at all.
 */
export function checkImportedScripts({ root, worker, config }: Shim): void {
  if (!worker || typeof root.importScripts !== 'function') return;
  const files = shippedScripts(config.scripts);
  const load = root.importScripts.bind(root);
  root.importScripts = (...urls: string[]) => {
    const wanted = [];
    for (const u of urls) {
      let url;
      try {
        url = new URL(u, location.href);
      } catch {
        wanted.push(u);
        continue;
      }
      const verdict = importVerdict(url, location.origin, files);
      if (verdict === 'skip') continue;
      if (verdict === 'missing') {
        throw new DOMException(
          "Failed to execute 'importScripts' on 'WorkerGlobalScope': The script at '" +
            url.href +
            "' failed to load.",
          'NetworkError',
        );
      }
      wanted.push(u);
    }
    if (wanted.length) return load(...wanted);
    return undefined;
  };
}
