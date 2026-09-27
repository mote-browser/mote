/** Attributes sites put on elements for tests and accessibility, which rarely change between builds. */
const HOOK_ATTRIBUTES = ['data-testid', 'data-test', 'data-qa', 'data-cy', 'aria-label', 'name', 'role'];

/**
 * A class worth hanging a rule on: a word, not a build artefact — no long runs
 * of digits, and none of the prefixes CSS-in-JS libraries generate.
 */
export function isStableClass(name: string): boolean {
  return (
    /^[a-zA-Z][\w-]{2,29}$/.test(name) &&
    !/\d{3,}/.test(name) &&
    !/^(css|sc|jsx|emotion|svelte|styles?)-/.test(name)
  );
}

/** Whether `selector` matches exactly one element; false when it isn't valid. */
export function isUnique(document: Document, selector: string): boolean {
  try {
    return document.querySelectorAll(selector).length === 1;
  } catch {
    return false;
  }
}

/**
 * A CSS selector that matches `element` alone, preferring what survives a
 * redesign: its id, a test or accessibility hook, its stable classes, and only
 * as a last resort its position in the tree.
 */
export function selectorFor(element: Element): string {
  const document = element.ownerDocument;
  const byId = element.id && `#${CSS.escape(element.id)}`;
  if (byId && isUnique(document, byId)) return byId;

  const tag = CSS.escape(element.localName);
  for (const hook of HOOK_ATTRIBUTES) {
    const value = element.getAttribute(hook);
    if (!value) continue;
    const byHook = `${tag}[${hook}="${CSS.escape(value)}"]`;
    if (isUnique(document, byHook)) return byHook;
  }

  // An SVG element's className is an animated string, not a list of words.
  const classes =
    element.className && typeof element.className === 'string'
      ? element.className.trim().split(/\s+/).filter(isStableClass)
      : [];
  if (classes.length) {
    const byClass = `${tag}.${classes.map((name) => CSS.escape(name)).join('.')}`;
    if (isUnique(document, byClass)) return byClass;
  }

  return pathTo(element);
}

/** A child-by-child path to `element`, anchored on the nearest ancestor with a unique id. */
function pathTo(element: Element): string {
  const document = element.ownerDocument;
  const parts: string[] = [];
  let node: Element | null = element;
  while (node && node.nodeType === Node.ELEMENT_NODE && node !== document.documentElement) {
    const byId = node.id && `#${CSS.escape(node.id)}`;
    if (byId && isUnique(document, byId)) {
      parts.unshift(byId);
      break;
    }
    const tag = CSS.escape(node.localName);
    const parent: Element | null = node.parentElement;
    if (!parent) {
      parts.unshift(tag);
      break;
    }
    const current = node;
    const kin = [...parent.children].filter(
      (sibling) => sibling.localName === current.localName && sibling.namespaceURI === current.namespaceURI,
    );
    parts.unshift(kin.length > 1 ? `${tag}:nth-of-type(${kin.indexOf(current) + 1})` : tag);
    node = parent;
  }
  return parts.join(' > ');
}
