// Hands the page's passkey requests (window events from `passkey-relay`) to
// Swift (PasskeyRelay.bridge in Passkeys.swift) and dispatches the replies
// back as window events.
//
// Injected at document start into every frame, in Mote's isolated content
// world, which pages can't reach. Swift learns the calling frame's origin and
// web view from WebKit, never from the event, and the document from the name
// the bridge draws for it here, which the page can't read: a request belongs to
// the document that made it, and only that document can cancel it.

import { parseRequest } from './lib/passkey-messages';
import type { PasskeyAnswer } from './lib/passkey-messages';
import { randomHex } from './lib/passkeys';

/** The message handler's name and the event names shared with `passkey-relay`. */
declare const moteConfig: { handler: string; askEvent: string; answerEvent: string };

/** A handler added with `addScriptMessageHandler`, which answers each message. */
interface ReplyingHandler {
  postMessage(message: unknown): Promise<unknown>;
}

declare global {
  interface Window {
    /** Set once the bridge listens in this frame. */
    __motePasskeyBridge?: boolean;
  }
}

const handler = window.webkit?.messageHandlers?.[moteConfig.handler] as ReplyingHandler | undefined;

if (handler && !window.__motePasskeyBridge) {
  window.__motePasskeyBridge = true;
  const documentName = randomHex(16);
  window.addEventListener(moteConfig.askEvent, (event) => {
    const message = parseRequest((event as CustomEvent<unknown>).detail);
    if (!message) return;
    message.document = documentName;
    const answer = (reply: unknown): void => {
      const detail: PasskeyAnswer = { token: message.token, reply: reply as PasskeyAnswer['reply'] };
      window.dispatchEvent(new CustomEvent(moteConfig.answerEvent, { detail: JSON.stringify(detail) }));
    };
    const cancelling = message.kind === 'cancel';
    // A WebKit message handler, not window.postMessage: there is no target origin.
    // oxlint-disable-next-line unicorn/require-post-message-target-origin
    handler.postMessage(message).then(
      (reply) => {
        if (!cancelling) answer(reply);
      },
      () => {
        if (!cancelling) answer(null);
      },
    );
  });
}
