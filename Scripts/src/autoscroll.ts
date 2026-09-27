// Middle-button autoscroll: a middle click outside links drops an anchor and
// scrolls toward the pointer, faster with distance. Swift (AutoScroll.swift)
// injects it and switches it off with `window.__moteAutoScrollOff`.

import { anchorBadge, HOLD_MS, DEAD_ZONE, INTERACTIVE, scrollContainer, speed } from './autoscroll/scrolling';

declare global {
  interface Window {
    __moteAutoScroll?: boolean;
    __moteAutoScrollOff?: boolean;
  }
}

interface Scrolling {
  x: number;
  y: number;
  dx: number;
  dy: number;
  since: number;
  target: Element;
  badge: HTMLElement;
  cursor: string;
  frame: number;
}

const MIDDLE_BUTTON = 1;

window.__moteAutoScrollOff = false;

if (!window.__moteAutoScroll) {
  window.__moteAutoScroll = true;

  let active: Scrolling | null = null;
  // The button whose press just stopped scrolling. Its click belongs to that
  // stop; on a link it would otherwise follow it or open a new tab.
  let swallowButton = -1;

  const tick = (): void => {
    if (!active) return;
    active.target.scrollBy(speed(active.dx), speed(active.dy));
    active.frame = requestAnimationFrame(tick);
  };

  const move = (event: MouseEvent): void => {
    if (!active) return;
    active.dx = event.clientX - active.x;
    active.dy = event.clientY - active.y;
  };

  const stop = (): void => {
    if (!active) return;
    cancelAnimationFrame(active.frame);
    active.badge.remove();
    document.documentElement.style.cursor = active.cursor;
    removeEventListener('mousemove', move, true);
    active = null;
  };

  addEventListener(
    'mousedown',
    (event) => {
      swallowButton = -1;
      if (active) {
        event.preventDefault();
        event.stopPropagation();
        stop();
        swallowButton = event.button;
        return;
      }
      if (event.button !== MIDDLE_BUTTON || window.__moteAutoScrollOff) return;
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest(INTERACTIVE)) return;
      event.preventDefault();
      active = {
        x: event.clientX,
        y: event.clientY,
        dx: 0,
        dy: 0,
        since: performance.now(),
        target: scrollContainer(target),
        badge: anchorBadge(event.clientX, event.clientY),
        cursor: document.documentElement.style.cursor,
        frame: 0,
      };
      document.documentElement.style.cursor = 'all-scroll';
      addEventListener('mousemove', move, true);
      active.frame = requestAnimationFrame(tick);
    },
    true,
  );

  // Held down and dragged: releasing the button stops scrolling.
  addEventListener(
    'mouseup',
    (event) => {
      if (
        active &&
        event.button === MIDDLE_BUTTON &&
        performance.now() - active.since > HOLD_MS &&
        (Math.abs(active.dx) > DEAD_ZONE || Math.abs(active.dy) > DEAD_ZONE)
      ) {
        stop();
        swallowButton = MIDDLE_BUTTON;
      }
    },
    true,
  );

  const swallowClick = (event: MouseEvent): void => {
    if (event.button === swallowButton) {
      swallowButton = -1;
      event.preventDefault();
      event.stopPropagation();
    } else if (event.button === MIDDLE_BUTTON && active) {
      event.preventDefault();
    }
  };
  addEventListener('click', swallowClick, true);
  addEventListener('auxclick', swallowClick, true);
  addEventListener(
    'keydown',
    (event) => {
      if (active && event.key === 'Escape') {
        event.preventDefault();
        stop();
      }
    },
    true,
  );
  addEventListener('wheel', stop, { capture: true, passive: true });
  addEventListener('blur', stop);
  document.addEventListener('visibilitychange', stop);
}
