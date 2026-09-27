// Tools/bench `tap`: where an element is, so Swift (Bench.swift) can send real
// mouse events there. Called in the page's content world.

import { centreInView, findTarget } from './bench-locate/target';

/** The centre of the element `selector` names, in page points, or null when nothing matches. */
export function run(selector: string): [number, number] | null {
  const element = findTarget(document, selector);
  return element ? centreInView(element) : null;
}
