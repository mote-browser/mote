import { describe, expect, it } from 'vitest';
import { linkAddress, MAX_ADDRESS_LENGTH } from '../src/status-line/link';

function pathTo(html: string, selector: string): EventTarget[] {
  document.body.innerHTML = html;
  const path: EventTarget[] = [];
  for (let node: Element | null = document.querySelector(selector); node; node = node.parentElement)
    path.push(node);
  return [...path, document, window];
}

describe('linkAddress', () => {
  it('resolves the nearest link around the pointer', () => {
    expect(linkAddress(pathTo('<a href="https://example.com/page"><span id="t">Go</span></a>', '#t'))).toBe(
      'https://example.com/page',
    );
  });

  it('is empty outside links and for script links', () => {
    expect(linkAddress(pathTo('<p id="t">Text</p>', '#t'))).toBe('');
    expect(linkAddress(pathTo('<a id="t" href="javascript:void(0)">Run</a>', '#t'))).toBe('');
  });

  it('skips anchors without an address', () => {
    expect(
      linkAddress(pathTo('<a href="https://example.com/outer"><a id="t" name="x">In</a></a>', '#t')),
    ).toBe('');
  });

  it('truncates very long addresses', () => {
    const long = `https://example.com/${'a'.repeat(1000)}`;
    expect(linkAddress(pathTo(`<a id="t" href="${long}">Long</a>`, '#t'))).toHaveLength(MAX_ADDRESS_LENGTH);
  });
});
