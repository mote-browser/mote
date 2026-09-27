/** An icon a page declares with `<link rel="…icon…">`; attributes are lowercased, missing ones empty. */
export interface DeclaredIcon {
  /** The absolute address. */
  href: string;
  rel: string;
  sizes: string;
  type: string;
  media: string;
}

/** Every icon the document declares, in document order. Swift ranks them (Favicons.rank). */
export function declaredIcons(document: Document): DeclaredIcon[] {
  const icons: DeclaredIcon[] = [];
  for (const link of document.querySelectorAll<HTMLLinkElement>('link[rel]')) {
    const rel = attribute(link, 'rel');
    if (!rel.includes('icon')) continue;
    icons.push({
      href: link.href,
      rel,
      sizes: attribute(link, 'sizes'),
      type: attribute(link, 'type'),
      media: attribute(link, 'media'),
    });
  }
  return icons;
}

function attribute(link: Element, name: string): string {
  return (link.getAttribute(name) || '').toLowerCase();
}
