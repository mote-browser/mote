/** Longest address sent to Swift; the status line truncates long addresses anyway. */
export const MAX_ADDRESS_LENGTH = 600;

/**
 * The absolute address of the first link in an event's composed path, or an empty
 * string. The composed path reaches links inside open shadow trees, where the
 * event target stops at the shadow host.
 */
export function linkAddress(path: readonly EventTarget[]): string {
  for (const node of path) {
    if (!(node instanceof Element) || (node.localName !== 'a' && node.localName !== 'area')) continue;
    const href = hrefOf(node);
    if (!href) continue;
    try {
      const address = new URL(href, node.baseURI).href;
      return address.startsWith('javascript:') ? '' : address.slice(0, MAX_ADDRESS_LENGTH);
    } catch {
      return '';
    }
  }
  return '';
}

/** An SVG link's `href` is an animated string whose value may be relative. */
function hrefOf(link: Element): string | undefined {
  const href: unknown = (link as Element & { href?: unknown }).href;
  if (typeof href === 'string') return href;
  if (href instanceof SVGAnimatedString) return href.baseVal;
  return undefined;
}
