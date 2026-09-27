// chrome.action (and the older chrome.browserAction).

import { resolved } from './callbacks';
import { createEvent } from './events';
import { fill } from './members';
import type { Shim } from './types';

/**
 * The popup an extension sets for its button, told to the browser too:
 * Mote opens a popup itself (see Extensions.press), and has to know
 * which page it is now. The browser is told the page and the tab's index,
 * or -1 for every tab (`action.popup`).
 */
export function tellPopups({ chrome, put, native }: Shim): void {
  for (const name of ['action', 'browserAction']) {
    const action = chrome[name];
    if (!action || typeof action.setPopup !== 'function') continue;
    const setPopup = action.setPopup.bind(action);
    put(action, 'setPopup', (details: { popup?: string; tabId?: number } = {}, callback?: unknown) => {
      const tell = (index: number) => native('action.popup', [details.popup || '', index]).catch(() => {});
      if (typeof details.tabId === 'number' && chrome.tabs) {
        chrome.tabs.get(details.tabId).then(
          (t: { index: number }) => tell(t.index),
          () => {},
        );
      } else tell(-1);
      return setPopup(details, callback);
    });
  }
}

export function fillAction(shim: Shim): void {
  fill(shim, 'action', {
    getUserSettings: resolved({ isOnToolbar: true }),
    onUserSettingsChanged: createEvent(),
    setBadgeTextColor: resolved(undefined),
    getBadgeTextColor: resolved([255, 255, 255, 255]),
  });
}
