// Who has something to say about a message, told between the
// extension's worker and its own pages on a channel they share (one
// origin): each says, as soon as its listeners have run, whether it
// answers or lets the message pass, and the sender says so of what
// it sends. A page with nothing to say can then stay silent only
// as long as someone else may still answer (see the end of `dispatch`
// in messaging.ts).
// A page in a website's frame is on the website's side of the
// channel and takes no part; it waits, as before.

import { randomId } from './ids';
import type { Shim } from './types';

export const CHANNEL_NAME = 'mote-messages';

/** Longest message, as JSON, that is told about; a longer one is simply waited for. */
const MAX_KEY_LENGTH = 4000;

/** How long what was said about a message is remembered. */
const REMEMBERED_MS = 30000;

export type Verdict = 'answers' | 'passes';

/** What is said about one message: by the worker (`from: "worker"`), or a page by its id. */
export interface VerdictNews {
  key: string;
  from: string;
  verdict: Verdict;
  /** Said by one that heard the message, not the one that sent it. */
  heard?: boolean;
  at: number;
}

/** What goes on the channel. */
export type ChannelNews =
  | VerdictNews
  /** A page that listens for messages, as it starts to, and in answer to a newcomer. */
  | { hello: true; from: string; where: string }
  /** A page that no longer listens. */
  | { bye: true; from: string }
  /** Who is still there? */
  | { roll: true; from: string }
  /** Still here, said to the one that asked. */
  | { here: true; from: string; to: string };

/** What was said about one message. */
export interface VerdictEntry {
  at: number;
  worker: VerdictNews | null;
  pages: Map<string, VerdictNews>;
}

/** The message as a key to what is said about it, or null when it is too long or not JSON. */
export function messageKey(message: unknown): string | null {
  try {
    const key = JSON.stringify(message);
    return key && key.length < MAX_KEY_LENGTH ? key : null;
  } catch {
    return null;
  }
}

/** Takes in a verdict, forgetting old ones; the entry for a key goes last, as the newest. */
export function recordVerdict(
  verdicts: Map<string, VerdictEntry>,
  news: VerdictNews,
  now: number,
): VerdictEntry {
  for (const [key, entry] of verdicts) {
    if (now - entry.at > REMEMBERED_MS) verdicts.delete(key);
    else break;
  }
  const entry = verdicts.get(news.key) || { at: now, worker: null, pages: new Map() };
  verdicts.delete(news.key);
  verdicts.set(news.key, entry);
  entry.at = now;
  if (news.from === 'worker') entry.worker = news;
  else entry.pages.set(news.from, news);
  return entry;
}

export interface Verdicts {
  channel: BroadcastChannel | null;
  /** This page's id on the channel. */
  me: string;
  /** The pages that listen, as they come and go. */
  peers: Set<string>;
  verdicts: Map<string, VerdictEntry>;
  /** Checks of pages waiting on others' verdicts, run whenever one comes. */
  waiting: Set<() => void>;
  /** Those taking the roll: each hears who says it is here. */
  present: Set<(id: string) => void>;
  /**
   * Pages that are there but didn't hear the last message sent to all —
   * WebKit doesn't bring every message to every page. Not waited for
   * until they say something about one they heard.
   */
  deaf: Set<string>;
  /** Says what this context makes of a message: its answer, or that it lets it pass. */
  tell(message: unknown, verdict: Verdict, heard?: boolean): void;
  /** Starts waiting to be waited for: this page listens for messages. */
  join(): void;
  leave(): void;
}

export function createVerdicts({ root, inContent, embedded, background }: Shim): Verdicts {
  const channel =
    !inContent && !embedded && typeof BroadcastChannel === 'function'
      ? new BroadcastChannel(CHANNEL_NAME)
      : null;
  const me = randomId();
  const peers = new Set<string>();
  const verdicts = new Map<string, VerdictEntry>();
  const waiting = new Set<() => void>();
  const present = new Set<(id: string) => void>();
  const deaf = new Set<string>();
  // Only a page that listens for messages is waited for: one that
  // doesn't never hears them, so never says anything about them.
  let listening = false;
  const post = (news: ChannelNews): void => channel!.postMessage(news);

  const tell = (message: unknown, verdict: Verdict, heard?: boolean): void => {
    const key = channel && messageKey(message);
    if (key) post({ key, from: background ? 'worker' : me, verdict, heard, at: Date.now() } as VerdictNews);
  };
  const join = (): void => {
    if (channel && !background && !listening) {
      listening = true;
      post({ hello: true, from: me, where: location.pathname });
    }
  };
  const leave = (): void => {
    if (channel && !background && listening) {
      listening = false;
      post({ bye: true, from: me });
    }
  };

  if (channel) {
    channel.onmessage = ({ data }: MessageEvent<any>) => {
      if (!data || data.from === me) return;
      if (!background && data.hello) {
        const known = peers.has(data.from);
        peers.add(data.from);
        if (!known && listening) post({ hello: true, from: me, where: location.pathname });
        return;
      }
      if (data.bye) {
        peers.delete(data.from);
        waiting.forEach((check) => check());
        return;
      }
      // A popup that closes is thrown away without a word; so a page
      // left waiting asks who is still there.
      if (data.roll) {
        if (listening && !background) post({ here: true, from: me, to: data.from });
        return;
      }
      if (data.here) {
        if (data.to === me) present.forEach((hear) => hear(data.from));
        return;
      }
      if (typeof data.key !== 'string') return;
      if (data.from !== 'worker') {
        peers.add(data.from);
        if (data.heard) deaf.delete(data.from);
      }
      recordVerdict(verdicts, data, Date.now());
      waiting.forEach((check) => check());
    };
    if (!background) {
      try {
        root.addEventListener('pagehide', () => leave());
      } catch {}
    }
  }

  return { channel, me, peers, verdicts, waiting, present, deaf, tell, join, leave };
}
