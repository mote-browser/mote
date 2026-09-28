/** The scroll position Swift receives: the offset from the top, and the most it can be. */
export interface ScrollPosition {
  y: number;
  max: number;
}

/** Never zero, so Swift can divide by it. */
export function scrollPosition(window: Window): ScrollPosition {
  const root = window.document.documentElement;
  return {
    y: window.scrollY || root.scrollTop || 0,
    max: Math.max(1, (root.scrollHeight || 0) - window.innerHeight),
  };
}

/** How far through the page, in whole percent: the steps the reading bar moves in (readingFraction in Swift). */
export function readingStep({ y, max }: ScrollPosition): number {
  return Math.round(Math.min(1, Math.max(0, y / max)) * 100);
}
