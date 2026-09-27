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
