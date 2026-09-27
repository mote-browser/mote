// Chrome's settings objects (chrome.privacy, chrome.proxy): get, set and
// clear, answered by the browser, and an event. chrome.contentSettings
// answers that everything is allowed.

import { nativeCall } from './callbacks';
import { createEvent, type ShimEvent } from './events';
import { putNamespace } from './namespaces';
import type { Callback, Shim } from './types';

/** A setting: its methods are native requests named `setting.get:<name>` and so on. */
export interface Setting {
  get: ReturnType<typeof nativeCall>;
  set: ReturnType<typeof nativeCall>;
  clear: ReturnType<typeof nativeCall>;
  onChange: ShimEvent;
}

export function setting(shim: Shim, name: string): Setting {
  return {
    get: nativeCall(shim, 'setting.get:' + name),
    set: nativeCall(shim, 'setting.set:' + name),
    clear: nativeCall(shim, 'setting.clear:' + name),
    onChange: createEvent(),
  };
}

function settings(shim: Shim, prefix: string, names: readonly string[]): Record<string, Setting> {
  return Object.fromEntries(names.map((n) => [n, setting(shim, prefix + '.' + n)]));
}

export const PRIVACY_SETTINGS = {
  services: [
    'alternateErrorPagesEnabled',
    'autofillAddressEnabled',
    'autofillCreditCardEnabled',
    'autofillEnabled',
    'passwordSavingEnabled',
    'safeBrowsingEnabled',
    'safeBrowsingExtendedReportingEnabled',
    'searchSuggestEnabled',
    'spellingServiceEnabled',
    'translationServiceEnabled',
  ],
  network: ['networkPredictionEnabled', 'webRTCIPHandlingPolicy'],
  websites: [
    'adMeasurementEnabled',
    'doNotTrackEnabled',
    'fledgeEnabled',
    'hyperlinkAuditingEnabled',
    'protectedContentEnabled',
    'referrersEnabled',
    'relatedWebsiteSetsEnabled',
    'thirdPartyCookiesAllowed',
    'topicsEnabled',
  ],
} as const;

export function definePrivacy(shim: Shim): void {
  putNamespace(shim, 'privacy', {
    services: settings(shim, 'privacy.services', PRIVACY_SETTINGS.services),
    network: settings(shim, 'privacy.network', PRIVACY_SETTINGS.network),
    websites: settings(shim, 'privacy.websites', PRIVACY_SETTINGS.websites),
    IPHandlingPolicy: {
      DEFAULT: 'default',
      DEFAULT_PUBLIC_AND_PRIVATE_INTERFACES: 'default_public_and_private_interfaces',
      DEFAULT_PUBLIC_INTERFACE_ONLY: 'default_public_interface_only',
      DISABLE_NON_PROXIED_UDP: 'disable_non_proxied_udp',
    },
  });
}

const CONTENT_SETTINGS = [
  'automaticDownloads',
  'autoVerify',
  'camera',
  'clipboard',
  'cookies',
  'images',
  'javascript',
  'location',
  'microphone',
  'notifications',
  'plugins',
  'popups',
  'sound',
];

function contentSetting() {
  return {
    get: (_details: unknown, cb?: Callback) => {
      const v = { setting: 'allow' };
      if (cb) cb(v);
      else return Promise.resolve(v);
      return undefined;
    },
    set: (_details: unknown, cb?: Callback) => {
      if (cb) cb();
      else return Promise.resolve();
      return undefined;
    },
    clear: (_details: unknown, cb?: Callback) => {
      if (cb) cb();
      else return Promise.resolve();
      return undefined;
    },
    getResourceIdentifiers: (cb?: Callback) => {
      if (cb) cb([]);
      else return Promise.resolve([]);
      return undefined;
    },
  };
}

export function defineContentSettings(shim: Shim): void {
  putNamespace(
    shim,
    'contentSettings',
    Object.fromEntries(CONTENT_SETTINGS.map((n) => [n, contentSetting()])),
  );
}

export function defineProxy(shim: Shim): void {
  putNamespace(shim, 'proxy', { settings: setting(shim, 'proxy.settings'), onProxyError: createEvent() });
}
