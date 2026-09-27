// Tools/bench `click`, `type` and `submit`: acts on an element from inside the
// page. Called from Swift (Bench.swift) in the page's content world.

import { act } from './bench-act/actions';

/** Returns 'ok', or why the action couldn't be done. */
export function run(verb: string, selector: string, text: string): string {
  return act(document, verb, selector, text);
}
