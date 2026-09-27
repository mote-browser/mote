// The start of every user script's file (chrome.userScripts), written by
// ExtensionShims.userScriptFile: decides whether the script runs at this
// address, and in Chrome's USER_SCRIPT world gives it its restricted `chrome`.
// Called there before the script's code, which declares `chrome` from what this
// returns; null stops the script.

import { userScriptChrome, type UserScriptChrome } from './user-script/chrome';
import { globsAllow } from './user-script/globs';

export interface UserScriptStart {
  /** Only in the USER_SCRIPT world. */
  chrome?: UserScriptChrome;
}

export function run(
  includeGlobs: string[],
  excludeGlobs: string[],
  userWorld: boolean,
): UserScriptStart | null {
  if (!globsAllow(location.href, includeGlobs, excludeGlobs)) return null;
  return userWorld ? { chrome: userScriptChrome((globalThis as any).chrome.runtime) } : {};
}
