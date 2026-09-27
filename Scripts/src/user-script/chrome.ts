import { USER_SCRIPT_PORT_PREFIX, type UserScriptMessage } from '../lib/user-scripts';

/** What a user script in Chrome's USER_SCRIPT world is given as `chrome` (and `browser`). */
export interface UserScriptChrome {
  runtime: {
    id: string;
    getURL(path: string): string;
    readonly lastError: unknown;
    sendMessage(message: unknown, ...rest: unknown[]): unknown;
    connect(info?: { name?: string }): unknown;
  };
}

/**
 * Chrome's USER_SCRIPT world, over `runtime` of the isolated world the script
 * runs in: messages go tagged, so the extension's worker hands them to
 * onUserScriptMessage and onUserScriptConnect rather than onMessage and onConnect.
 */
export function userScriptChrome(runtime: any): UserScriptChrome {
  return {
    runtime: {
      id: runtime.id,
      getURL: (path) => runtime.getURL(path),
      get lastError() {
        return runtime.lastError;
      },
      sendMessage: (message, ...rest) =>
        runtime.sendMessage(
          { __moteUserScript: true, message } satisfies UserScriptMessage,
          ...rest.filter((r) => typeof r === 'function' || (r && typeof r === 'object')),
        ),
      connect: (info) =>
        runtime.connect({ ...info, name: USER_SCRIPT_PORT_PREFIX + ((info && info.name) || '') }),
    },
  };
}
