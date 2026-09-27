import { describe, expect, it } from 'vitest';
import { middleClickAddress } from '../src/middle-click/link';

function pathTo(html: string, selector: string): EventTarget[] {
  document.body.innerHTML = html;
  const path: EventTarget[] = [];
  for (let node: Element | null = document.querySelector(selector); node; node = node.parentElement)
    path.push(node);
  return [...path, document, window];
}

describe('middleClickAddress', () => {
  it('finds the link around the clicked element', () => {
    expect(middleClickAddress(pathTo('<a href="https://example.com/page"><b id="t">Go</b></a>', '#t'))).toBe(
      'https://example.com/page',
    );
  });

  it('treats an image map area as a link', () => {
    expect(middleClickAddress(pathTo('<map><area id="t" href="https://example.com/area"></map>', '#t'))).toBe(
      'https://example.com/area',
    );
  });

  it('skips anchors without an address and is null outside links', () => {
    expect(
      middleClickAddress(pathTo('<a href="https://example.com/outer"><a id="t" name="x">In</a></a>', '#t')),
    ).toBeNull();
    expect(middleClickAddress(pathTo('<p id="t">Text</p>', '#t'))).toBeNull();
  });
});
