// What a user script in Chrome's USER_SCRIPT world (user-script.ts) and the
// extension's shim (extension-shims/user-scripts.ts) agree on.

/** The prefix of a port's name opened from the USER_SCRIPT world. */
export const USER_SCRIPT_PORT_PREFIX = 'mote-us:';

/** A message sent from the USER_SCRIPT world, for onUserScriptMessage. */
export interface UserScriptMessage {
  __moteUserScript: true;
  message: unknown;
}
