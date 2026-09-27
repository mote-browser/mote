import { describe, expect, it } from 'vitest';
import { declaredIcons } from '../src/favicon-probe/icons';

describe('declaredIcons', () => {
  it('lists icon links with lowercased attributes, skipping other links', () => {
    document.head.innerHTML = `
      <link rel="canonical" href="https://example.com/">
      <link rel="Icon" href="https://example.com/a.png" sizes="32X32" type="image/PNG">
      <link rel="apple-touch-icon" href="https://example.com/touch.png" media="(prefers-color-scheme: DARK)">`;
    expect(declaredIcons(document)).toEqual([
      { href: 'https://example.com/a.png', rel: 'icon', sizes: '32x32', type: 'image/png', media: '' },
      {
        href: 'https://example.com/touch.png',
        rel: 'apple-touch-icon',
        sizes: '',
        type: '',
        media: '(prefers-color-scheme: dark)',
      },
    ]);
  });
});
