import { beforeEach, describe, expect, it } from 'vitest';
import { clip, elementName, elementShape } from '../src/element-picker/describe';
import { isStableClass, isUnique, selectorFor } from '../src/element-picker/selector';
import '../src/element-picker';

function byTest(id: string): Element {
  const element = document.querySelector(`[data-t="${id}"]`);
  if (!element) throw new Error(`No element ${id}`);
  return element;
}

/** The selector for the element marked `data-t="<id>"`, checked to select that element alone. */
function pick(id: string): string {
  const element = byTest(id);
  element.removeAttribute('data-t');
  const selector = selectorFor(element);
  expect([...document.querySelectorAll(selector)]).toEqual([element]);
  return selector;
}

describe('isStableClass', () => {
  it('accepts words', () => {
    for (const name of ['sidebar', 'cookie-banner', 'Promo_box', 'ad2'])
      expect(isStableClass(name)).toBe(true);
  });

  it('rejects build artefacts, very short or long names, and generated prefixes', () => {
    for (const name of [
      'a1',
      'x',
      '1col',
      'box-12345',
      'css-1q2w3e',
      'sc-bdVaJa',
      'jsx-42',
      'emotion-x',
      'svelte-abc',
      'styles-module',
      'style-x',
      'a'.repeat(31),
    ])
      expect(isStableClass(name)).toBe(false);
  });
});

describe('isUnique', () => {
  beforeEach(() => {
    document.body.innerHTML = '<p class="a"></p><p class="a"></p><span></span>';
  });

  it('counts matches', () => {
    expect(isUnique(document, 'span')).toBe(true);
    expect(isUnique(document, '.a')).toBe(false);
    expect(isUnique(document, 'div')).toBe(false);
  });

  it('is false for an invalid selector', () => {
    expect(isUnique(document, 'p[')).toBe(false);
  });
});

describe('selectorFor', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  it('prefers a unique id', () => {
    document.body.innerHTML = '<div id="promo" class="sidebar" data-t="x"></div>';
    expect(pick('x')).toBe('#promo');
  });

  // happy-dom's selector engine doesn't read CSS escapes: ids and values that
  // need them are covered against WebKit in MoteTests/ElementPickerScriptTests.
  it('keeps ids that are identifiers as they are', () => {
    document.body.innerHTML = '<div id="日本" data-t="x"></div><div id="-top_bar" data-t="y"></div>';
    expect(pick('x')).toBe('#日本');
    expect(pick('y')).toBe('#-top_bar');
  });

  it('skips an id the page repeats', () => {
    document.body.innerHTML = '<div id="dup" data-testid="first" data-t="x"></div><div id="dup"></div>';
    expect(pick('x')).toBe('div[data-testid="first"]');
  });

  it('uses test and accessibility hooks, in order', () => {
    document.body.innerHTML = `
      <section data-qa="promo" role="banner" data-t="a"></section>
      <button aria-label="close" data-t="b"></button>
      <nav role="navigation" data-t="c"></nav>`;
    expect(pick('a')).toBe('section[data-qa="promo"]');
    expect(pick('b')).toBe('button[aria-label="close"]');
    expect(pick('c')).toBe('nav[role="navigation"]');
  });

  it('skips hooks that are not unique', () => {
    document.body.innerHTML = '<a role="link" class="more-link" data-t="x"></a><a role="link"></a>';
    expect(pick('x')).toBe('a.more-link');
  });

  it('uses only stable classes', () => {
    document.body.innerHTML =
      '<div class="css-1a2b3c card promo-box x9 sc-xyz" data-t="x"></div><div class="card"></div>';
    expect(pick('x')).toBe('div.card.promo-box');
  });

  it('falls back to a path anchored on the nearest unique id', () => {
    document.body.innerHTML = `
      <main id="content"><ul><li>One</li><li><span>Two</span></li></ul></main>
      <main id="other"><ul><li><span>Three</span></li></ul></main>`;
    const two = document.querySelectorAll('span')[0];
    if (!two) throw new Error('No span');
    two.setAttribute('data-t', 'x');
    expect(pick('x')).toBe('#content > ul > li:nth-of-type(2) > span');
  });

  it('falls back to a path from the body without ids', () => {
    document.body.innerHTML = '<div><p>A</p></div><div><p>B</p><p data-t="x">C</p></div>';
    expect(pick('x')).toBe('body > div:nth-of-type(2) > p:nth-of-type(2)');
  });

  it('ignores the class of an SVG element', () => {
    document.body.innerHTML =
      '<div><svg class="icon"></svg></div><div><svg class="icon" data-t="x"></svg></div>';
    expect(pick('x')).toBe('body > div:nth-of-type(2) > svg');
  });

  it('is stable: the same element gives the same selector', () => {
    document.body.innerHTML = '<div class="sidebar"></div>';
    const element = document.querySelector('.sidebar');
    if (!element) throw new Error('No sidebar');
    expect(selectorFor(element)).toBe(selectorFor(element));
  });
});

/** The name of the first element in `html`. */
function nameOf(html: string): string {
  document.body.innerHTML = html;
  const element = document.body.firstElementChild;
  if (!element) throw new Error('No element');
  return elementName(element);
}

describe('elementName', () => {
  it('prefers what the element calls itself', () => {
    expect(nameOf('<nav aria-label="  Main menu "></nav>')).toBe('Main menu');
    expect(nameOf('<div title="Newsletter">Sign up</div>')).toBe('Newsletter');
  });

  it('then its kind, then its role', () => {
    expect(nameOf('<aside>Links</aside>')).toBe('Sidebar');
    expect(nameOf('<div role="banner">Hello</div>')).toBe('Banner');
  });

  it('names an element called like a member of Object.prototype by its tag', () => {
    for (const name of ['constructor', 'toString', '__proto__', 'hasOwnProperty']) {
      const element = document.createElementNS('http://www.w3.org/1999/xhtml', name);
      expect(elementName(element)).toBe(name);
    }
  });

  it('then its words, clipped, or its tag', () => {
    expect(nameOf('<div>  Cookies   are\n here  </div>')).toBe('Cookies are here');
    expect(nameOf(`<div>${'word '.repeat(20)}</div>`)).toBe(`${'word '.repeat(8)}…`);
    expect(nameOf('<div></div>')).toBe('div');
  });
});

function box(left: number, top: number, width: number, height: number): DOMRectReadOnly {
  return { left, top, width, height } as DOMRectReadOnly;
}

describe('elementShape', () => {
  const viewport = { width: 900, height: 600 };

  it('gives the size and the part of the window', () => {
    expect(elementShape(box(0, 0, 200.4, 100.6), viewport)).toBe('200×101 · top left');
    expect(elementShape(box(350, 250, 200, 100), viewport)).toBe('200×100 · middle centre');
    expect(elementShape(box(700, 500, 200, 100), viewport)).toBe('200×100 · bottom right');
  });
});

describe('clip', () => {
  it('cuts long text with an ellipsis', () => {
    expect(clip('abcdef', 3)).toBe('abc…');
    expect(clip('abc', 3)).toBe('abc');
  });
});

/** The selectors of the rules in the <style> element `id`. */
function selectorsIn(id: string): string[] {
  const style = document.getElementById(id) as HTMLStyleElement | null;
  return [...(style?.sheet?.cssRules ?? [])].map((rule) => (rule as CSSStyleRule).selectorText);
}

describe('peek and unpeek', () => {
  beforeEach(() => {
    document.head.innerHTML = '';
    document.body.innerHTML = '<div id="banner"></div><div id="other"></div>';
  });

  it('hide every selector but one, and outline that one', () => {
    window.__moteVeil?.peek(['#other'], '#banner');
    expect(selectorsIn('mote-hidden-elements')).toEqual(['#other']);
    expect(selectorsIn('mote-peek')).toEqual(['#banner']);

    window.__moteVeil?.unpeek(['#banner', '#other']);
    expect(selectorsIn('mote-hidden-elements')).toEqual(['#banner', '#other']);
    expect(selectorsIn('mote-peek')).toEqual([]);
  });

  it('never let a selector add rules of its own', () => {
    const breakout = '#none {} body { display: none !important; } #x';
    window.__moteVeil?.peek([breakout, '#other'], breakout);
    expect(selectorsIn('mote-hidden-elements')).toEqual(['#other']);
    expect(selectorsIn('mote-peek')).toEqual([]);
  });
});
