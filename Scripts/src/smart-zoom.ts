// Smart zoom (two-finger double-tap): picks the scale that fits the block under
// the pointer to the view, or the way back when already zoomed in. Called from
// Swift (PageView.smartMagnify in Tab.swift) in the page's content world.

import { columnAround, type Tap, ZOOMED_IN, zoomInto, zoomOut } from './smart-zoom/zoom';

/**
 * `x` and `y` are the tapped point and `width` the view's width, in view points;
 * `scale` is the current page scale. Returns a `Zoom` as JSON, or null when
 * nothing is under the pointer.
 */
export function run(x: number, y: number, scale: number, width: number): string | null {
  const tap: Tap = { x, y, scale, width, scrollX: window.scrollX, scrollY: window.scrollY };
  if (scale > ZOOMED_IN) return JSON.stringify(zoomOut(tap));
  const element = document.elementFromPoint(x / scale, y / scale);
  if (!element) return null;
  return JSON.stringify(zoomInto(columnAround(element, width / scale), tap));
}
