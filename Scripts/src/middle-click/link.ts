/**
 * The address of the first link in a middle click's composed path, or null.
 *
 * The path, not the parents: a link inside an open shadow root is on it too. An
 * <area> of an image map is a link, and so is an SVG <a>, whose `href` is an
 * object that holds the address as written.
 */
export function middleClickAddress(path: readonly EventTarget[]): string | null {
  for (const node of path) {
    const tag = node instanceof Element ? node.localName : '';
    if (tag !== 'a' && tag !== 'area') continue;
    const href = linkHref(node as Element);
    if (href) return href;
  }
  return null;
}

/** An HTML link's resolved `href`, or an SVG link's resolved against the element's base. */
function linkHref(link: Element): string {
  const href: unknown = (link as Element & { href?: unknown }).href;
  if (!href || typeof href !== 'object') return typeof href === 'string' ? href : '';
  try {
    const written = (href as SVGAnimatedString).baseVal;
    return written ? new URL(written, link.baseURI).href : '';
  } catch {
    return '';
  }
}
