// Hides the elements someone chose to hide on a site (ElementHider.swift). Swift
// gives it the site's selectors as `moteConfig` — data, never CSS text — and
// adds it at document start into the main frame, in Mote's isolated content
// world, so hidden elements never appear; it also runs it on the current
// document when the list changes. Each run replaces what the last one hid.

import { hideElements } from './lib/element-hiding';

declare const moteConfig: { selectors: string[] };

hideElements(document, Array.isArray(moteConfig.selectors) ? moteConfig.selectors : []);
