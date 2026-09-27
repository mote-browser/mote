import { beforeEach, describe, expect, it } from 'vitest';
import {
  articleTitle,
  cleanArticle,
  findArticle,
  proseScore,
  resolveImages,
  siteName,
} from '../src/reader/article';

const paragraph = `<p>${'Mote keeps the article and drops what was arranged around it. '.repeat(3)}</p>`;
const article = `<article id="story"><h1>The headline</h1>${paragraph.repeat(4)}</article>`;

function element(html: string): Element {
  const container = document.createElement('div');
  container.innerHTML = html;
  return container;
}

describe('proseScore', () => {
  it('is zero with fewer than two paragraphs', () => {
    expect(proseScore(element(paragraph))).toBe(0);
  });

  it('is zero with too little text', () => {
    expect(proseScore(element('<p>Short.</p><p>Also short.</p>'))).toBe(0);
  });

  it('is penalized by links', () => {
    const plain = proseScore(element(paragraph.repeat(4)));
    const linked = proseScore(element(paragraph.repeat(4) + '<a href="/">Home</a>'.repeat(3)));
    expect(plain).toBeGreaterThan(0);
    expect(linked).toBeLessThan(plain / 10);
  });
});

describe('findArticle', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  it('picks the element with the most prose over a link rail', () => {
    document.body.innerHTML = `<nav>${'<a href="/">Link</a>'.repeat(30)}</nav>${article}<aside>${paragraph.repeat(3)}${'<a href="/r">Related</a>'.repeat(20)}</aside>`;
    expect(findArticle(document)?.id).toBe('story');
  });

  it('finds nothing on a page without prose', () => {
    document.body.innerHTML = '<p>Short.</p><a href="/">Home</a>';
    expect(findArticle(document)).toBeNull();
  });
});

describe('resolveImages', () => {
  it('uses the lazy-loaded address behind a placeholder', () => {
    const container = element(
      '<img src="data:image/gif;base64,R0lG" data-src="https://example.com/real.jpg">',
    );
    resolveImages(container);
    expect(container.querySelector('img')?.getAttribute('src')).toBe('https://example.com/real.jpg');
    expect(container.querySelector('img')?.getAttribute('loading')).toBe('eager');
  });

  it('copies a lazy srcset when there is none', () => {
    const container = element('<img src="a.jpg" data-srcset="a.jpg 1x, a@2x.jpg 2x">');
    resolveImages(container);
    expect(container.querySelector('img')?.getAttribute('srcset')).toBe('a.jpg 1x, a@2x.jpg 2x');
  });
});

describe('cleanArticle', () => {
  it('removes clutter, keeps video players and drops other frames and empty images', () => {
    const container = element(`
      <p>Text</p><nav>Menu</nav><button>Share</button><div aria-hidden="true">Hidden</div>
      <iframe src="https://www.youtube.com/embed/x" width="560" height="315"></iframe>
      <iframe src="https://ads.example.com/frame"></iframe>
      <img src=""><img src="data:image/png;base64,AAAA"><img src="https://example.com/photo.jpg">`);
    cleanArticle(container);
    expect(container.querySelector('nav, button, [aria-hidden]')).toBeNull();
    const frames = [...container.querySelectorAll('iframe')];
    expect(frames.map((frame) => frame.getAttribute('src'))).toEqual(['https://www.youtube.com/embed/x']);
    expect(frames[0]?.hasAttribute('width')).toBe(false);
    expect([...container.querySelectorAll('img')].map((image) => image.getAttribute('src'))).toEqual([
      'https://example.com/photo.jpg',
    ]);
  });
});

describe('articleTitle and siteName', () => {
  it('prefers the headline over the document title', () => {
    document.title = 'Page title';
    document.body.innerHTML = '<h1>  The headline  </h1>';
    expect(articleTitle(document)).toBe('The headline');
    document.body.innerHTML = '';
    expect(articleTitle(document)).toBe('Page title');
  });

  it('drops www. from the host', () => {
    expect(siteName('www.example.com')).toBe('example.com');
    expect(siteName('news.example.com')).toBe('news.example.com');
  });
});
