import { describe, expect, it } from 'vitest';
import { menuImageAddress } from '../src/image-menu/image';

/** An image inside a link, with the loaded address and width WebKit would report. */
function image(currentSrc: string, naturalWidth: number): HTMLImageElement {
  document.body.innerHTML = '<a href="/"><img><span>caption</span></a>';
  const element = document.querySelector('img')!;
  Object.defineProperty(element, 'currentSrc', { value: currentSrc });
  Object.defineProperty(element, 'naturalWidth', { value: naturalWidth });
  return element;
}

describe('menuImageAddress', () => {
  it('is the address of a loaded image', () => {
    expect(menuImageAddress(image('https://example.com/a.png', 300))).toBe('https://example.com/a.png');
    expect(menuImageAddress(image('data:image/png;base64,AAAA', 300))).toBe('data:image/png;base64,AAAA');
  });

  it('is null for tracking pixels, broken images and unsupported schemes', () => {
    expect(menuImageAddress(image('https://example.com/pixel.gif', 1))).toBeNull();
    expect(menuImageAddress(image('', 0))).toBeNull();
    expect(menuImageAddress(image('ftp://example.com/a.png', 300))).toBeNull();
  });

  it('finds an image of an XHTML page, whose tag names are lower case', () => {
    const element = image('https://example.com/a.png', 300);
    Object.defineProperty(element, 'tagName', { value: 'img' });
    expect(menuImageAddress(element)).toBe('https://example.com/a.png');
  });

  it('is null outside images', () => {
    image('https://example.com/a.png', 300);
    expect(menuImageAddress(document.querySelector('span'))).toBeNull();
  });
});
