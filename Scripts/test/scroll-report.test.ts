import { describe, expect, it } from 'vitest';
import { readingStep, scrollPosition } from '../src/scroll-report/position';

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

describe('readingStep', () => {
  it('is the whole percent scrolled, as the reading bar shows it', () => {
    expect(readingStep({ y: 333, max: 1000 })).toBe(33);
    expect(readingStep({ y: 0, max: 1000 })).toBe(0);
  });

  it('stays between 0 and 100 when the page bounces past its ends', () => {
    expect(readingStep({ y: -40, max: 1000 })).toBe(0);
    expect(readingStep({ y: 2000, max: 1000 })).toBe(100);
  });
});
