// Sizes an extension popup the way Blink auto-sizes Chrome's (25×25 to 800×600).
// Called from Swift (ExtensionPopup.swift) in the popup page's content world.

import {
  clampHeight,
  clampWidth,
  contentWidth,
  ownExtent,
  type Sizing,
  withStyle,
} from './popup-size/measure';

declare global {
  interface Window {
    /** What the page's own size was last time, kept between calls. */
    __moteSizing?: Sizing;
  }
}

/**
 * `fit`: the popup's size, measured while the view is 25 pt square. Width: the
 * page's own width, else min-content, else the scroll width for very narrow pages.
 * Height: measured at that width.
 *
 * `grow`: the width by the same rules without the memory (a width the page sets
 * counts only when it is wider than the view), and the scroll height when the
 * page overflows, else 0. Swift only grows the popup from these.
 *
 * Returns null when there is no document yet. Inline styles are restored.
 */
export function run(stage: 'fit' | 'grow'): [number, number] | null {
  const root = document.documentElement;
  if (!root) return null;
  return stage === 'fit' ? fit(root) : grow(root);
}

function fit(root: HTMLElement): [number, number] {
  const sizing = (window.__moteSizing ??= {});
  const ownWidth = ownExtent(sizing, 'w', root.getBoundingClientRect().width, innerWidth);
  const width = clampWidth(ownWidth ?? contentWidth(root));
  const height = withStyle(root, { width: `${width}px` }, () => {
    const measured = root.getBoundingClientRect().height;
    const ownHeight = ownExtent(sizing, 'h', measured, innerHeight);
    if (ownHeight !== null) return ownHeight;
    root.style.setProperty('height', 'auto', 'important');
    root.style.setProperty('min-height', '0', 'important');
    return root.getBoundingClientRect().height;
  });
  return [width, clampHeight(height)];
}

function grow(root: HTMLElement): [number, number] {
  const own = root.getBoundingClientRect().width;
  const width = own > innerWidth + 1 ? own : contentWidth(root);
  const height = root.scrollHeight > root.clientHeight ? root.scrollHeight : 0;
  return [width, height];
}
