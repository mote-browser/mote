// chrome.declarativeNetRequest as Chrome has it, and rules put the way
// WebKit takes them.

import { refuse, resolved } from './callbacks';
import { createEvent } from './events';
import { enumOf, fill } from './members';
import type { Callback, Shim } from './types';

export function fillDeclarativeNetRequest(shim: Shim, resourceTypes: Record<string, string>): void {
  fill(shim, 'declarativeNetRequest', {
    GUARANTEED_MINIMUM_STATIC_RULES: 30000,
    MAX_NUMBER_OF_REGEX_RULES: 1000,
    MAX_NUMBER_OF_SESSION_RULES: 5000,
    MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES: 5000,
    MAX_NUMBER_OF_UNSAFE_SESSION_RULES: 5000,
    MAX_GETMATCHEDRULES_CALLS_PER_INTERVAL: 20,
    GETMATCHEDRULES_QUOTA_INTERVAL: 10,
    DYNAMIC_RULESET_ID: '_dynamic',
    SESSION_RULESET_ID: '_session',
    getAvailableStaticRuleCount: resolved(30000),
    getDisabledRuleIds: resolved([]),
    updateStaticRules: resolved(undefined),
    testMatchOutcome: refuse(shim, 'declarativeNetRequest.testMatchOutcome'),
    onRuleMatchedDebug: createEvent(),
    RuleActionType: {
      BLOCK: 'block',
      REDIRECT: 'redirect',
      ALLOW: 'allow',
      UPGRADE_SCHEME: 'upgradeScheme',
      MODIFY_HEADERS: 'modifyHeaders',
      ALLOW_ALL_REQUESTS: 'allowAllRequests',
    },
    ResourceType: resourceTypes,
    HeaderOperation: enumOf('append', 'set', 'remove'),
    DomainType: { FIRST_PARTY: 'firstParty', THIRD_PARTY: 'thirdParty' },
    RequestMethod: enumOf('connect', 'delete', 'get', 'head', 'options', 'patch', 'post', 'put', 'other'),
    UnsupportedRegexReason: { SYNTAX_ERROR: 'syntaxError', MEMORY_LIMIT_EXCEEDED: 'memoryLimitExceeded' },
  });
}

/** A rule, as far as the shim reads it. */
export interface Rule {
  id?: number;
  action?: { redirect?: { url?: unknown; extensionPath?: string }; [key: string]: unknown } | undefined;
  condition?:
    | { resourceTypes?: string[]; excludedResourceTypes?: string[]; [key: string]: unknown }
    | undefined;
  [key: string]: unknown;
}

/** Resource types WebKit has no name for. */
const UNKNOWN_TYPES = new Set(['webtransport', 'webbundle', 'object']);

/**
 * A rule put the way WebKit takes it: a redirect to one of the extension's
 * own files by path rather than by address (`base` is the extension's root
 * URL), and without the resource types it has no name for. Null when no
 * resource type is left for it.
 */
export function mendRule(rule: unknown, base: string): unknown {
  if (!rule || typeof rule !== 'object') return rule;
  const given = rule as Rule;
  const r: Rule = {
    ...given,
    action: given.action && { ...given.action },
    condition: given.condition && { ...given.condition },
  };
  const redirect = r.action && r.action.redirect;
  if (redirect && typeof redirect.url === 'string' && base && redirect.url.startsWith(base)) {
    r.action!.redirect = { extensionPath: '/' + redirect.url.slice(base.length) };
  }
  const c = r.condition;
  if (c && Array.isArray(c.resourceTypes)) {
    c.resourceTypes = c.resourceTypes.filter((t) => !UNKNOWN_TYPES.has(t));
    if (!c.resourceTypes.length) return null;
  }
  if (c && Array.isArray(c.excludedResourceTypes)) {
    c.excludedResourceTypes = c.excludedResourceTypes.filter((t) => !UNKNOWN_TYPES.has(t));
  }
  return r;
}

/** The index of the rule WebKit refused, from its error. */
export function refusedRuleIndex(error: unknown): number | null {
  const at = /rule at index (\d+)/.exec(String(error && (error as Error).message));
  return at ? Number(at[1]) : null;
}

/**
 * Rules WebKit can't carry out — a header it doesn't know how to set,
 * say — are refused one by one, where Chrome would take them all. The
 * rest still go in: one rule Mote can't honour shouldn't cost an
 * extension every other rule, or its startup.
 * Before WebKit sees them, rules are put the way it takes them (`mendRule`).
 */
export function mendRules(shim: Shim): void {
  const { chrome, runtime, put, native } = shim;
  const dnr = chrome.declarativeNetRequest;
  const base = (() => {
    try {
      return runtime.getURL('');
    } catch {
      return '';
    }
  })();
  if (dnr && typeof dnr.isRegexSupported === 'function') {
    const original = dnr.isRegexSupported.bind(dnr);
    put(dnr, 'isRegexSupported', (options: unknown, callback?: Callback) => {
      const p = Promise.resolve(original(options)).then(
        (r) => r || { isSupported: false, reason: 'syntaxError' },
        () => ({ isSupported: false, reason: 'syntaxError' }),
      );
      if (typeof callback !== 'function') return p;
      p.then((r) => callback(r));
      return undefined;
    });
  }
  if (!dnr) return;
  for (const name of ['updateSessionRules', 'updateDynamicRules']) {
    if (typeof dnr[name] !== 'function') continue;
    const original = dnr[name].bind(dnr);
    const attempt = async (opts: any, left: number): Promise<unknown> => {
      try {
        return await original(opts);
      } catch (e) {
        const index = refusedRuleIndex(e);
        if (index === null || !Array.isArray(opts.addRules) || left <= 0) throw e;
        const rule = opts.addRules[index];
        try {
          native('debug.error', [
            'declarativeNetRequest: rule ' + (rule && rule.id) + ' left out — ' + (e as Error).message,
          ]).catch(() => {});
        } catch {}
        return attempt(
          { ...opts, addRules: opts.addRules.filter((_: unknown, i: number) => i !== index) },
          left - 1,
        );
      }
    };
    put(dnr, name, (options: any = {}, callback?: Callback) => {
      if (options && Array.isArray(options.addRules)) {
        options = {
          ...options,
          addRules: options.addRules.map((rule: unknown) => mendRule(rule, base)).filter(Boolean),
        };
      }
      const p = attempt(options, 100);
      if (typeof callback !== 'function') return p;
      p.then(
        () => callback(),
        (e) => shim.withLastError(e, callback),
      );
      return undefined;
    });
  }
}
