/** Clicks, submits or (any other verb) types `text` into the element `selector` names. Returns 'ok', or why it couldn't. */
export function act(document: Document, verb: string, selector: string, text: string): string {
  const element = document.querySelector(selector) as HTMLElement | null;
  if (!element) return 'nothing matches ' + selector;
  element.scrollIntoView?.({ block: 'center', inline: 'nearest' });
  if (verb === 'click') {
    element.focus?.();
    element.click();
    return 'ok';
  }
  if (verb === 'submit') return submit(element, selector);
  element.focus?.();
  return typeInto(element, text, selector);
}

function submit(element: HTMLElement, selector: string): string {
  const form =
    element.localName === 'form'
      ? (element as HTMLFormElement)
      : (element as HTMLInputElement).form || element.closest('form');
  if (!form) return 'no form around ' + selector;
  if (form.requestSubmit) form.requestSubmit();
  else form.submit();
  return 'ok';
}

/**
 * Types `value` into a text field or an editable element, or picks the option of
 * a <select> whose value or text it is. Local names rather than tag names, which
 * XHTML pages keep in lower case.
 */
function typeInto(element: HTMLElement, value: string, selector: string): string {
  if (element.isContentEditable) {
    element.textContent = value;
    element.dispatchEvent(new InputEvent('input', { bubbles: true, data: value, inputType: 'insertText' }));
    return 'ok';
  }
  switch (element.localName) {
    case 'input':
      setValue(element, window.HTMLInputElement.prototype, value);
      return 'ok';
    case 'textarea':
      setValue(element, window.HTMLTextAreaElement.prototype, value);
      return 'ok';
    case 'select':
      return choose(element as HTMLSelectElement, value, selector);
    default:
      return selector + ' takes no text';
  }
}

/**
 * Sets the value through the native setter and dispatches input and change
 * events, so frameworks that track the value (React) notice the change.
 */
export function setValue(
  element: HTMLElement,
  prototype: object,
  value: string,
  events: string[] = ['input', 'change'],
): void {
  const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
  if (setter) setter.call(element, value);
  else (element as HTMLInputElement).value = value;
  changed(element, events);
}

/** Selects the option whose value is `wanted`, or else whose text is, alone. */
function choose(select: HTMLSelectElement, wanted: string, selector: string): string {
  const options = [...select.options];
  const option =
    options.find((candidate) => candidate.value === wanted) ??
    options.find((candidate) => candidate.text.trim() === wanted.trim());
  if (!option) return `no option ${wanted} in ${selector}`;
  for (const candidate of options) candidate.selected = candidate === option;
  changed(select);
  return 'ok';
}

function changed(element: HTMLElement, events: string[] = ['input', 'change']): void {
  for (const event of events) element.dispatchEvent(new Event(event, { bubbles: true }));
}
