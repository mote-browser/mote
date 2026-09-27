// Reading mode: replaces the page with its main article.
// Called from Swift (Reader.swift), which reads the returned value.

import { articleTitle, cleanArticle, findArticle, resolveImages, siteName } from './reader/article';
import { READER_ID, READER_STYLE } from './reader/style';

export type ReaderResult = 'read' | 'none';

export function run(): ReaderResult {
  const article = findArticle(document);
  if (!article) return 'none';

  resolveImages(article);
  const title = articleTitle(document);

  const container = document.createElement('div');
  container.id = READER_ID;
  container.innerHTML = article.innerHTML;
  cleanArticle(container);

  const heading = document.createElement('h1');
  heading.textContent = title;
  const source = document.createElement('p');
  source.className = 'mote-from';
  source.textContent = siteName(location.host);
  container.prepend(heading, source);

  const style = document.createElement('style');
  style.textContent = READER_STYLE;

  document.body.replaceChildren(container);
  document.head.append(style);
  window.scrollTo(0, 0);
  return 'read';
}
