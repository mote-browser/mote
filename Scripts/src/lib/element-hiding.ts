/** The <style> element hiding the elements someone chose to hide on a site. */
export const HIDDEN_ELEMENTS_STYLE_ID = 'mote-hidden-elements';

/** What each hiding rule declares. */
const HIDDEN = { display: 'none' };

/**
 * Hides the elements `selectors` select, replacing what was hidden before: one
 * rule per selector, so one the browser can't parse leaves the others working.
 */
export function hideElements(document: Document, selectors: readonly string[]): number {
  return writeRules(document, HIDDEN_ELEMENTS_STYLE_ID, selectors, HIDDEN);
}

/**
 * Replaces the rules of the <style> element `id` — created at the end of <head>
 * when missing — with one rule per selector, declaring each of `declarations` as
 * `!important`. Returns how many selectors made a rule.
 *
 * Selectors are stored, and could say anything: never CSS text. Each is built
 * into a rule through the CSSOM, which takes exactly one rule or throws, and a
 * selector is skipped unless it parses as a selector on its own and makes a
 * style rule that declares nothing of its own — so no selector can add rules,
 * declarations or imports to the page.
 */
export function writeRules(
  document: Document,
  id: string,
  selectors: readonly string[],
  declarations: Readonly<Record<string, string>>,
): number {
  const sheet = emptySheet(document, id);
  if (!sheet) return 0;
  let written = 0;
  for (const selector of selectors) {
    const rule = emptyRule(document, sheet, selector);
    if (!rule) continue;
    for (const [name, value] of Object.entries(declarations))
      rule.style.setProperty(name, value, 'important');
    written++;
  }
  return written;
}

/** The sheet of the <style> element `id`, emptied. */
function emptySheet(document: Document, id: string): CSSStyleSheet | null {
  let style = document.getElementById(id) as HTMLStyleElement | null;
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    (document.head || document.documentElement).appendChild(style);
  }
  // Drops text the page may have written into it, then the rules left: an
  // element already empty keeps its sheet, and the rules put there before.
  style.textContent = '';
  const sheet = style.sheet;
  while (sheet?.cssRules.length) sheet.deleteRule(sheet.cssRules.length - 1);
  return sheet;
}

/** An empty style rule for `selector` at the end of `sheet`, or null when `selector` is anything else. */
function emptyRule(document: Document, sheet: CSSStyleSheet, selector: unknown): CSSStyleRule | null {
  if (typeof selector !== 'string' || !isSelector(document, selector)) return null;
  let index: number;
  try {
    index = sheet.insertRule(`${selector} {}`, sheet.cssRules.length);
  } catch {
    return null;
  }
  const rule = sheet.cssRules[index] as CSSStyleRule | undefined;
  // Anything but an empty style rule came from the selector.
  const nested = (rule as { cssRules?: CSSRuleList } | undefined)?.cssRules?.length ?? 0;
  if (!rule || !('selectorText' in rule) || !rule.style || rule.style.length > 0 || nested > 0) {
    sheet.deleteRule(index);
    return null;
  }
  return rule;
}

/** Whether `selector` parses as a selector: a brace, semicolon or at-rule outside a string doesn't. */
function isSelector(document: Document, selector: string): boolean {
  if (!selector.trim()) return false;
  try {
    document.createDocumentFragment().querySelector(selector);
    return true;
  } catch {
    return false;
  }
}
