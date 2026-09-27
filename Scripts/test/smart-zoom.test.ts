import { describe, expect, it } from 'vitest';
import { type Tap, zoomInto, zoomOut } from '../src/smart-zoom/zoom';

const tap: Tap = { x: 300, y: 200, scale: 1, width: 1000, scrollX: 0, scrollY: 500 };

describe('zoomInto', () => {
  it('fits a narrow column to the view, keeping the tapped point at its height', () => {
    expect(zoomInto({ left: 100, width: 476 }, tap)).toEqual({ scale: 2, x: 88, y: 600 });
  });

  it('never zooms past 3×', () => {
    expect(zoomInto({ left: 0, width: 50 }, tap).scale).toBe(3);
  });

  it('doubles the scale when fitting would barely change it', () => {
    expect(zoomInto({ left: 0, width: 950 }, tap).scale).toBe(2);
  });
});

describe('zoomOut', () => {
  it('returns to scale 1 from the current scroll offset', () => {
    expect(zoomOut({ ...tap, scale: 2, scrollX: 400, scrollY: 400 })).toEqual({ scale: 1, x: 250, y: 300 });
  });

  it('never scrolls before the start of the page', () => {
    expect(zoomOut({ ...tap, scale: 2, scrollX: 0, scrollY: 0 })).toEqual({ scale: 1, x: 0, y: 0 });
  });
});
