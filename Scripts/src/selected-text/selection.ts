/**
 * The text selected in `document`: a focused text field's selection first, then
 * the document's. Same-origin frames are searched recursively; cross-origin
 * frames and password fields yield an empty string.
 *
 * Local names rather than `instanceof`, since a frame's elements come from
 * another realm; and not tag names, which XHTML pages keep in lower case.
 */
export function selectedText(document: Document): string {
  const focused = document.activeElement;
  if (focused && (focused.localName === 'iframe' || focused.localName === 'frame')) {
    try {
      const inner = (focused as HTMLIFrameElement).contentDocument;
      return inner ? selectedText(inner) : '';
    } catch {
      return '';
    }
  }
  const isPassword = focused?.localName === 'input' && (focused as HTMLInputElement).type === 'password';
  if (focused && (focused.localName === 'textarea' || (focused.localName === 'input' && !isPassword))) {
    const field = focused as HTMLInputElement | HTMLTextAreaElement;
    try {
      const from = field.selectionStart;
      const to = field.selectionEnd;
      if (typeof from === 'number' && typeof to === 'number' && to > from) return field.value.slice(from, to);
    } catch {
      // Inputs without a text selection (e.g. type=email in some engines) throw.
    }
  }
  if (isPassword) return '';
  return document.getSelection()?.toString() ?? '';
}
