// Namespaces for what Mote can't do, answered the way Chrome answers when it
// can't — so that code that reaches for them at startup carries on.

import { refuse } from './callbacks';
import { createEvent } from './events';
import { putNamespace } from './namespaces';
import type { Callback, Shim } from './types';

function events(...names: string[]) {
  return Object.fromEntries(names.map((n) => [n, createEvent()]));
}

/**
 * Rules that show a button on matching pages: every button is always
 * shown in Mote, so there is nothing for them to do.
 */
function rules() {
  return {
    addRules: (r: unknown, cb?: Callback) => {
      if (cb) cb(r || []);
    },
    removeRules: (_ids: unknown, cb?: Callback) => {
      if (cb) cb();
    },
    getRules: (ids: unknown, cb?: Callback) => {
      const f = typeof ids === 'function' ? (ids as Callback) : cb;
      if (f) f([]);
    },
  };
}

export function defineUnavailable(shim: Shim): void {
  putNamespace(shim, 'omnibox', {
    setDefaultSuggestion: () => {},
    ...events('onInputStarted', 'onInputChanged', 'onInputEntered', 'onInputCancelled', 'onDeleteSuggestion'),
  });
  putNamespace(shim, 'tabCapture', {
    capture: refuse(shim, 'tabCapture.capture'),
    getMediaStreamId: refuse(shim, 'tabCapture.getMediaStreamId'),
    getCapturedTabs: (cb?: Callback) => {
      if (cb) cb([]);
      else return Promise.resolve([]);
      return undefined;
    },
    onStatusChanged: createEvent(),
  });
  // The picker Chrome would show, cancelled: an empty stream id.
  putNamespace(shim, 'desktopCapture', {
    chooseDesktopMedia: (_sources: unknown, tab: unknown, cb?: Callback) => {
      const f = typeof tab === 'function' ? (tab as Callback) : cb;
      if (f) setTimeout(() => f('', {}));
      return 1;
    },
    cancelChooseDesktopMedia: () => {},
    DesktopCaptureSourceType: { SCREEN: 'screen', WINDOW: 'window', TAB: 'tab', AUDIO: 'audio' },
  });
  putNamespace(shim, 'pageCapture', { saveAsMHTML: refuse(shim, 'pageCapture.saveAsMHTML') });
  putNamespace(shim, 'debugger', {
    attach: refuse(shim, 'debugger.attach'),
    detach: refuse(shim, 'debugger.detach'),
    sendCommand: refuse(shim, 'debugger.sendCommand'),
    getTargets: (cb?: Callback) => {
      if (cb) cb([]);
      else return Promise.resolve([]);
      return undefined;
    },
    ...events('onEvent', 'onDetach'),
  });
  putNamespace(shim, 'gcm', {
    register: refuse(shim, 'gcm.register'),
    unregister: refuse(shim, 'gcm.unregister'),
    send: refuse(shim, 'gcm.send'),
    ...events('onMessage', 'onMessagesDeleted', 'onSendError'),
  });
  putNamespace(shim, 'instanceID', {
    getID: refuse(shim, 'instanceID.getID'),
    getToken: refuse(shim, 'instanceID.getToken'),
    deleteID: refuse(shim, 'instanceID.deleteID'),
    deleteToken: refuse(shim, 'instanceID.deleteToken'),
    getCreationTime: refuse(shim, 'instanceID.getCreationTime'),
    onTokenRefresh: createEvent(),
  });
  putNamespace(shim, 'declarativeContent', {
    onPageChanged: rules(),
    PageStateMatcher: function (this: object, o: object) {
      Object.assign(this, o);
    },
    ShowAction: function () {},
    ShowPageAction: function () {},
    SetIcon: function (this: object, o: object) {
      Object.assign(this, o);
    },
    RequestContentScript: function (this: object, o: object) {
      Object.assign(this, o);
    },
  });
}
