import { describe, expect, it } from 'vitest';
import {
  clampHeight,
  clampWidth,
  neededWidth,
  ownExtent,
  type Sizing,
  withStyle,
} from '../src/popup-size/measure';

describe('ownExtent', () => {
  it('takes and remembers an extent that differs from the view', () => {
    const sizing: Sizing = {};
    expect(ownExtent(sizing, 'w', 320, 25)).toBe(320);
    expect(sizing.w).toBe(320);
  });

  it('recognizes the remembered extent once the view has it', () => {
    expect(ownExtent({ w: 320 }, 'w', 320, 320.5)).toBe(320);
  });

  it('is null for a page that just fills the view', () => {
    expect(ownExtent({}, 'h', 25, 25)).toBeNull();
    expect(ownExtent({ h: 400 }, 'h', 25, 25)).toBeNull();
  });
});

describe('neededWidth and clamping', () => {
  it('uses the scroll width only for very narrow pages', () => {
    expect(neededWidth(250, 600)).toBe(250);
    expect(neededWidth(40, 180)).toBe(180);
  });

  it("keeps to Blink's popup limits, rounding up", () => {
    expect(clampWidth(10)).toBe(25);
    expect(clampWidth(300.2)).toBe(301);
    expect(clampWidth(2000)).toBe(800);
    expect(clampHeight(900)).toBe(600);
  });
});

describe('withStyle', () => {
  it("restores the element's own inline style, or its absence", () => {
    const element = document.createElement('div');
    element.setAttribute('style', 'color: red');
    expect(withStyle(element, { width: 'min-content' }, () => element.style.width)).toBe('min-content');
    expect(element.getAttribute('style')).toBe('color: red');

    const bare = document.createElement('div');
    withStyle(bare, { width: '10px' }, () => 0);
    expect(bare.hasAttribute('style')).toBe(false);
  });
});
