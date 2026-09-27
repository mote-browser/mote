import { beforeEach, describe, expect, it } from 'vitest';
import { act } from '../src/bench-act/actions';

beforeEach(() => {
  document.body.innerHTML = '';
});

describe('act', () => {
  it('types into a field and fires input and change', () => {
    document.body.innerHTML = '<input id="field">';
    const field = document.getElementById('field') as HTMLInputElement;
    const events: string[] = [];
    field.addEventListener('input', () => events.push('input'));
    field.addEventListener('change', () => events.push('change'));
    expect(act(document, 'type', '#field', 'hello')).toBe('ok');
    expect(field.value).toBe('hello');
    expect(events).toEqual(['input', 'change']);
  });

  it('types into a text area of an XHTML page, whose tag names are lower case', () => {
    document.body.innerHTML = '<textarea id="area"></textarea>';
    const area = document.getElementById('area') as HTMLTextAreaElement;
    Object.defineProperty(area, 'tagName', { value: 'textarea' });
    expect(act(document, 'type', '#area', 'hello')).toBe('ok');
    expect(area.value).toBe('hello');
  });

  it('picks the option of a select by its value or its text, and fires input and change', () => {
    document.body.innerHTML =
      '<select id="size"><option value="s">Small</option><option value="l">Large</option></select>';
    const size = document.getElementById('size') as HTMLSelectElement;
    const events: string[] = [];
    size.addEventListener('input', () => events.push('input'));
    size.addEventListener('change', () => events.push('change'));
    expect(act(document, 'type', '#size', 'l')).toBe('ok');
    expect(size.value).toBe('l');
    expect(act(document, 'type', '#size', 'Small')).toBe('ok');
    expect(size.value).toBe('s');
    expect(events).toEqual(['input', 'change', 'input', 'change']);
  });

  it('refuses an option a select does not have', () => {
    document.body.innerHTML = '<select id="size"><option value="s">Small</option></select>';
    expect(act(document, 'type', '#size', 'Huge')).toBe('no option Huge in #size');
    expect((document.getElementById('size') as HTMLSelectElement).value).toBe('s');
  });

  it('refuses to type into what takes no text', () => {
    document.body.innerHTML = '<div id="box">Box</div><button id="go">Go</button>';
    expect(act(document, 'type', '#box', 'hello')).toBe('#box takes no text');
    expect(act(document, 'type', '#go', 'hello')).toBe('#go takes no text');
    expect(document.getElementById('box')?.textContent).toBe('Box');
  });

  it('submits a form of an XHTML page', () => {
    document.body.innerHTML = '<form id="f"><input name="q"></form>';
    const form = document.getElementById('f') as HTMLFormElement;
    Object.defineProperty(form, 'tagName', { value: 'form' });
    let submitted = 0;
    form.requestSubmit = () => void submitted++;
    expect(act(document, 'submit', '#f', '')).toBe('ok');
    expect(submitted).toBe(1);
  });

  it('clicks', () => {
    document.body.innerHTML = '<button id="b">Go</button>';
    let clicks = 0;
    document.getElementById('b')?.addEventListener('click', () => clicks++);
    expect(act(document, 'click', '#b', '')).toBe('ok');
    expect(clicks).toBe(1);
  });

  it('explains what went wrong', () => {
    document.body.innerHTML = '<input id="lonely">';
    expect(act(document, 'click', '#none', '')).toBe('nothing matches #none');
    expect(act(document, 'submit', '#lonely', '')).toBe('no form around #lonely');
  });
});
