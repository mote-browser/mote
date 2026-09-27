/** Containers that may hold the article, scored by `proseScore`. */
const CANDIDATES = 'article, main, [role="main"], .post, .entry, .article, .content, #content, div, section';

/** Everything arranged around the words rather than part of them. Headers stay: the opening image often lives there. */
const CLUTTER =
  'script,style,noscript,form,nav,aside,footer,button,input,select,textarea,' +
  '[role="complementary"],[role="navigation"],[role="banner"],[aria-hidden="true"]';

/** Attributes lazy-loading libraries keep the real image address in. */
const LAZY_SOURCES = [
  'data-src',
  'data-original',
  'data-lazy-src',
  'data-lazy',
  'data-full-src',
  'data-hi-res-src',
  'data-image',
  'data-echo',
];

/** Video players whose embeds are part of an article; every other frame is dropped. */
const VIDEO_PLAYERS = /youtube|youtu\.be|vimeo|dailymotion|loom\.com|streamable|wistia|ted\.com/i;

/**
 * How much readable prose an element holds: its paragraph text, penalized by its
 * links, since navigation, related-content rails and comments are link-heavy.
 */
export function proseScore(element: Element): number {
  const paragraphs = element.querySelectorAll('p');
  if (paragraphs.length < 2) return 0;
  let letters = 0;
  for (const paragraph of paragraphs) letters += (paragraph.innerText || '').length;
  if (letters < 400) return 0;
  const links = element.querySelectorAll('a').length;
  return letters / (1 + links * 14);
}

/** The element with the most prose, or null when nothing reads like an article. */
export function findArticle(document: Document): Element | null {
  let best: Element | null = null;
  let bestScore = 0;
  for (const candidate of document.querySelectorAll(CANDIDATES)) {
    const score = proseScore(candidate);
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  return best;
}

/**
 * Writes each image's real address into `src` while the original page still
 * stands: `currentSrc` is what the browser chose after srcset and <picture>, and
 * lazy loaders keep the real address in data attributes behind a placeholder.
 */
export function resolveImages(article: Element): void {
  for (const image of article.querySelectorAll('img')) {
    image.setAttribute('loading', 'eager');
    let source = image.currentSrc || image.getAttribute('src') || '';
    const isPlaceholder = !source || source.startsWith('data:image') || image.naturalWidth <= 2;
    if (isPlaceholder) {
      const lazy = LAZY_SOURCES.map((name) => image.getAttribute(name)).find(Boolean);
      if (lazy) source = lazy;
    }
    if (source) image.setAttribute('src', source);
    const lazySet = image.getAttribute('data-srcset');
    if (lazySet && !image.getAttribute('srcset')) image.setAttribute('srcset', lazySet);
  }
}

/** Removes clutter, frames that aren't video players, and images with no source. */
export function cleanArticle(container: Element): void {
  for (const element of container.querySelectorAll(CLUTTER)) element.remove();

  for (const frame of container.querySelectorAll('iframe')) {
    const source = frame.getAttribute('src') || frame.getAttribute('data-src') || '';
    if (VIDEO_PLAYERS.test(source)) {
      frame.setAttribute('src', source);
      frame.removeAttribute('height');
      frame.removeAttribute('width');
    } else {
      frame.remove();
    }
  }

  for (const image of container.querySelectorAll('img')) {
    const source = image.getAttribute('src') || '';
    if (!source || source.startsWith('data:image')) image.remove();
  }
}

/** The page's own headline, or its title. */
export function articleTitle(document: Document): string {
  return document.querySelector('h1')?.innerText.trim() || document.title;
}

/** The host a page came from, without `www.`. */
export function siteName(host: string): string {
  return host.replace(/^www\./, '');
}
