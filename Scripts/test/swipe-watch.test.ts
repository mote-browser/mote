import { describe, expect, it } from 'vitest';
import { hasRoom, REPEAT_INTERVAL, rootCanScroll, shouldReport } from '../src/swipe-watch/scrollable';

describe('rootCanScroll', () => {
  it("uses the body's overflow when the root's is visible", () => {
    expect(rootCanScroll('visible', 'visible')).toBe(true);
    expect(rootCanScroll('visible', 'hidden')).toBe(false);
    expect(rootCanScroll('auto', 'hidden')).toBe(true);
    expect(rootCanScroll('clip', 'auto')).toBe(false);
  });
});

describe('hasRoom', () => {
  it('needs room in the direction of the swipe', () => {
    expect(hasRoom(0, 500, 10)).toBe(true);
    expect(hasRoom(0, 500, -10)).toBe(false);
    expect(hasRoom(500, 500, 10)).toBe(false);
    expect(hasRoom(500, 500, -10)).toBe(true);
  });

  it('ignores content that barely overflows', () => {
    expect(hasRoom(0, 1, 10)).toBe(false);
  });
});

describe('shouldReport', () => {
  it('reports changes at once and repeats an unchanged answer only after the interval', () => {
    expect(shouldReport({ taken: null, at: 0 }, false, 1000)).toBe(true);
    expect(shouldReport({ taken: false, at: 1000 }, true, 1010)).toBe(true);
    expect(shouldReport({ taken: true, at: 1000 }, true, 1010)).toBe(false);
    expect(shouldReport({ taken: true, at: 1000 }, true, 1000 + REPEAT_INTERVAL)).toBe(true);
  });
});
