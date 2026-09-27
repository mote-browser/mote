/** Blink's limits for an extension popup, in CSS pixels. */
export const MIN_SIZE = 25;
export const MAX_WIDTH = 800;
export const MAX_HEIGHT = 600;

/** Below this min-content width a page counts as very narrow, and its scroll width is used. */
const NARROW = 100;

/** The size the page last gave itself, remembered between measurements. */
export interface Sizing {
  w?: number;
  h?: number;
}

/**
 * The extent a page sets for itself along one axis, or null when it sets none.
 * An extent the page sets shows as one the view doesn't have, and is remembered;
 * one equal to the view is either filling it or the extent it was given last
 * time, which the memory tells apart.
 */
export function ownExtent(
  sizing: Sizing,
  axis: keyof Sizing,
  measured: number,
  viewport: number,
): number | null {
  if (Math.abs(measured - viewport) > 1) {
    sizing[axis] = measured;
    return measured;
  }
  const remembered = sizing[axis];
  if (remembered && Math.abs(remembered - viewport) <= 1) return remembered;
  return null;
}

/** The width a page needs: its min-content width, or its scroll width when that is very narrow. */
export function neededWidth(minContent: number, scrollWidth: number): number {
  return minContent >= NARROW ? minContent : Math.max(minContent, scrollWidth);
}

export function clampWidth(width: number): number {
  return Math.min(MAX_WIDTH, Math.max(MIN_SIZE, Math.ceil(width)));
}

export function clampHeight(height: number): number {
  return Math.min(MAX_HEIGHT, Math.max(MIN_SIZE, Math.ceil(height)));
}

/** Runs `measure` with `root`'s inline style overridden, then restores the page's own. */
export function withStyle<T>(root: HTMLElement, style: Record<string, string>, measure: () => T): T {
  const saved = root.getAttribute('style');
  for (const [name, value] of Object.entries(style)) root.style.setProperty(name, value, 'important');
  try {
    return measure();
  } finally {
    if (saved === null) root.removeAttribute('style');
    else root.setAttribute('style', saved);
  }
}

/** `neededWidth` for the page, measured with its width forced to min-content. */
export function contentWidth(root: HTMLElement): number {
  const minContent = withStyle(root, { width: 'min-content' }, () => root.getBoundingClientRect().width);
  return neededWidth(minContent, root.scrollWidth);
}
