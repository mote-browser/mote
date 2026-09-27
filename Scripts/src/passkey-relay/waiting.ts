// The page's requests waiting for Swift's answer, by token.

import { parseAnswer } from '../lib/passkey-messages';

type Settle = (reply: unknown) => void;

const mapGet = Map.prototype.get;
const mapSet = Map.prototype.set;
const mapDelete = Map.prototype.delete;
const apply = Reflect.apply;

/**
 * Requests by token, in a Map: a token like `toString` finds nothing it
 * wasn't given. Its methods were taken as the script started, so a page that
 * replaces Map's later sees none of it.
 */
export class Waiting {
  private readonly requests = new Map<string, Settle>();

  add(token: string, settle: Settle): void {
    apply(mapSet, this.requests, [token, settle]);
  }

  /** Forgets a request: the page let it go. */
  drop(token: string): void {
    apply(mapDelete, this.requests, [token]);
  }

  /** Settles the request an answer event's detail is for; false when it's for none. */
  answer(detail: unknown): boolean {
    const answer = parseAnswer(detail);
    if (!answer) return false;
    const settle = apply(mapGet, this.requests, [answer.token]) as Settle | undefined;
    if (!settle) return false;
    this.drop(answer.token);
    settle(answer.reply);
    return true;
  }
}
