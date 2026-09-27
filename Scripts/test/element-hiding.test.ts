import { beforeEach, describe, expect, it } from 'vitest';
import { HIDDEN_ELEMENTS_STYLE_ID, hideElements, writeRules } from '../src/lib/element-hiding';

beforeEach(() => {
  document.head.innerHTML = '';
  document.body.innerHTML = '';
});

/** The rules of the <style> element `id`, as text. */
function rules(id: string): string[] {
  const style = document.getElementById(id) as HTMLStyleElement | null;
  return [...(style?.sheet?.cssRules ?? [])].map((rule) => rule.cssText);
}

describe('writeRules', () => {
  it('writes one rule per selector with the given declarations', () => {
    expect(writeRules(document, 'test', ['#a', '.b > p'], { color: 'red' })).toBe(2);
    const sheet = (document.getElementById('test') as HTMLStyleElement).sheet!;
    expect(sheet.cssRules.length).toBe(2);
    const first = sheet.cssRules[0] as CSSStyleRule;
    expect(first.selectorText).toBe('#a');
    expect(first.style.getPropertyValue('color')).toBe('red');
    expect(first.style.getPropertyPriority('color')).toBe('important');
  });

  it('replaces what it wrote before', () => {
    writeRules(document, 'test', ['#a', '#b'], { color: 'red' });
    writeRules(document, 'test', ['#c'], { color: 'red' });
    expect(rules('test')).toHaveLength(1);
    expect((document.getElementById('test') as HTMLStyleElement).sheet?.cssRules[0]).toMatchObject({
      selectorText: '#c',
    });
    writeRules(document, 'test', [], { color: 'red' });
    expect(rules('test')).toEqual([]);
  });

  it('skips a selector that would break out of its rule, and keeps the others', () => {
    const breakouts = [
      '#none {} body { display: none !important; } #x',
      '#none } body { display: none !important',
      '#none { background: url(https://example.com/leak); x:',
      '#none, body { color: red; }',
      '@import url(https://example.com/leak.css);',
      '#none; body',
    ];
    expect(writeRules(document, 'test', [...breakouts, '#kept'], { display: 'none' })).toBe(1);
    const sheet = (document.getElementById('test') as HTMLStyleElement).sheet!;
    expect(sheet.cssRules.length).toBe(1);
    expect((sheet.cssRules[0] as CSSStyleRule).selectorText).toBe('#kept');
  });

  it('skips invalid selectors and what is not a string, one at a time', () => {
    const selectors = ['p[', '#a', '', 42, '::nonsense(', '.b'] as unknown as string[];
    expect(writeRules(document, 'test', selectors, { display: 'none' })).toBe(2);
    expect(rules('test')).toHaveLength(2);
  });

  // happy-dom's CSS parser can't read a brace inside a string; a selector like
  // [title="{ }"] is covered against WebKit in MoteTests/ElementHidingTests.
});

describe('hideElements', () => {
  it('hides the selected elements in the hidden-elements stylesheet', () => {
    document.body.innerHTML = '<div id="banner">Cookies?</div><p id="text">Text</p>';
    hideElements(document, ['#banner']);
    const style = document.getElementById(HIDDEN_ELEMENTS_STYLE_ID) as HTMLStyleElement;
    const rule = style.sheet?.cssRules[0] as CSSStyleRule;
    expect(rule.selectorText).toBe('#banner');
    expect(rule.style.getPropertyValue('display')).toBe('none');
    expect(rule.style.getPropertyPriority('display')).toBe('important');
  });

  it('reuses the stylesheet it made', () => {
    hideElements(document, ['#a']);
    hideElements(document, ['#b']);
    expect(document.querySelectorAll(`#${HIDDEN_ELEMENTS_STYLE_ID}`)).toHaveLength(1);
  });
});
