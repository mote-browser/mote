import { describe, expect, it } from 'vitest';
import { scrollPosition } from '../src/scroll-report/position';

function fakeWindow(scrollY: number, scrollTop: number, scrollHeight: number, innerHeight: number): Window {
  return {
    scrollY,
    innerHeight,
    document: { documentElement: { scrollTop, scrollHeight } },
  } as unknown as Window;
}

describe('scrollPosition', () => {
  it('reports the offset and how far the page can scroll', () => {
    expect(scrollPosition(fakeWindow(120, 0, 3000, 800))).toEqual({ y: 120, max: 2200 });
  });

  it('falls back to the root scroll offset', () => {
    expect(scrollPosition(fakeWindow(0, 40, 3000, 800)).y).toBe(40);
  });

  it('never reports a ceiling below 1', () => {
    expect(scrollPosition(fakeWindow(0, 0, 500, 800)).max).toBe(1);
  });
});
