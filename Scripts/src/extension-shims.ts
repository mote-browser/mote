// Chrome extension APIs WebKit lacks, filled in, and Chrome's behaviour where
// WebKit's differs. Written by ExtensionShims.prepare into every extension, as
// mote-shim.js: first in its worker (inline, or imported by a module worker),
// its pages and its content scripts, so it runs before the extension's code.
// Calls to the browser go as native messages to the `mote` application.

import { install } from './extension-shims/install';
import type { ShimConfig } from './extension-shims/types';

declare const moteConfig: ShimConfig;

install(globalThis, moteConfig);
