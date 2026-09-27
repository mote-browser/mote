/** Elements a `text=` selector can match: what a person would click. */
const CLICKABLE = 'button, a, [role=button], input[type=submit]';

/**
 * The element `selector` names: a CSS selector, or `text=Label` for the button or
 * link whose text (or value) is the label, ignoring case and surrounding spaces.
 */
export function findTarget(document: Document, selector: string): Element | null {
  if (!selector.startsWith('text=')) return document.querySelector(selector);
  const wanted = selector.slice(5).trim().toLowerCase();
  const matches = (element: Element): boolean => {
    const { innerText, value } = element as HTMLElement & { value?: string };
    return (innerText || value || '').trim().toLowerCase() === wanted;
  };
  return [...document.querySelectorAll(CLICKABLE)].find(matches) ?? null;
}

/** The centre of an element in viewport pixels, after scrolling it into view. */
export function centreInView(element: Element): [number, number] {
  element.scrollIntoView({ block: 'center', inline: 'nearest' });
  const rect = element.getBoundingClientRect();
  return [rect.left + rect.width / 2, rect.top + rect.height / 2];
}
