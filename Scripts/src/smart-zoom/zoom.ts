/** A page scale and the scroll offset, in page CSS pixels, to apply with it. */
export interface Zoom {
  scale: number;
  x: number;
  y: number;
}

/** Where the double-tap happened, in view points, and the view's state before it. */
export interface Tap {
  /** The tapped point in view points. */
  x: number;
  y: number;
  /** The current page scale. */
  scale: number;
  /** The view's width in points. */
  width: number;
  /** The page's scroll offset in CSS pixels, read before the scale changes (changing it resets the scroll). */
  scrollX: number;
  scrollY: number;
}

/** Above this scale the page counts as zoomed in, and a double-tap zooms back out. */
export const ZOOMED_IN = 1.05;
const MAX_SCALE = 3;
/** Room kept on each side of the fitted block. */
const PADDING = 12;
/** A fit barely larger than this isn't worth it; the scale doubles instead. */
const MIN_USEFUL_SCALE = 1.15;

/** Back to scale 1, keeping the tapped point where it was. */
export function zoomOut(tap: Tap): Zoom {
  const pageX = tap.x / tap.scale;
  const pageY = tap.y / tap.scale;
  return {
    scale: 1,
    x: Math.max(0, tap.scrollX + pageX - tap.x),
    y: Math.max(0, tap.scrollY + pageY - tap.y),
  };
}

/** Fits `block` (its left edge and width in page pixels) to the view, keeping the tapped point at the same height. */
export function zoomInto(block: { left: number; width: number }, tap: Tap): Zoom {
  const pageY = tap.y / tap.scale;
  let scale = Math.max(1, Math.min(MAX_SCALE, tap.width / (block.width + 2 * PADDING)));
  if (scale < MIN_USEFUL_SCALE) scale = Math.min(MAX_SCALE, tap.scale * 2);
  return {
    scale,
    x: Math.max(0, tap.scrollX + block.left - PADDING),
    y: Math.max(0, tap.scrollY + pageY - tap.y / scale),
  };
}

/**
 * The innermost block around `element` wide enough to be a column of something —
 * a paragraph's column, a card, a feed — rather than the whole page's layout,
 * which is what walking up to a wide ancestor finds. Falls back to the first
 * block of a reasonable size, then to the element itself.
 */
export function columnAround(element: Element, viewWidth: number): DOMRect {
  const enough = Math.max(240, viewWidth * 0.2);
  let best: DOMRect | null = null;
  const root = element.ownerDocument.documentElement;
  for (let node: Element | null = element; node && node !== root; node = node.parentElement) {
    const rect = node.getBoundingClientRect();
    if (rect.width < 80 || rect.height < 16) continue;
    const display = getComputedStyle(node).display;
    if (display === 'inline' || display === 'contents') continue;
    if (!best) best = rect;
    if (rect.width >= enough) {
      best = rect;
      break;
    }
  }
  return best ?? element.getBoundingClientRect();
}
