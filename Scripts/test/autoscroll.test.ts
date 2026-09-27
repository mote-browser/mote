import { describe, expect, it } from 'vitest';
import { anchorBadge, DEAD_ZONE, MAX_SPEED, speed } from '../src/autoscroll/scrolling';

describe('speed', () => {
  it('does nothing inside the dead zone', () => {
    expect(speed(0)).toBe(0);
    expect(speed(DEAD_ZONE)).toBe(0);
    expect(speed(-DEAD_ZONE)).toBe(0);
  });

  it('grows with distance, in the pointer direction', () => {
    expect(speed(40)).toBeGreaterThan(speed(20));
    expect(speed(-40)).toBe(-speed(40));
  });

  it('is capped', () => {
    expect(speed(10_000)).toBe(MAX_SPEED);
    expect(speed(-10_000)).toBe(-MAX_SPEED);
  });
});

describe('anchorBadge', () => {
  it('is centered on the anchor and ignores the pointer', () => {
    const badge = anchorBadge(100, 200);
    expect(badge.style.left).toBe('85px');
    expect(badge.style.top).toBe('185px');
    expect(badge.style.pointerEvents).toBe('none');
    badge.remove();
  });
});
