import { beforeEach, describe, expect, it } from 'vitest';
import { selectedText } from '../src/selected-text/selection';

function select(id: string): void {
  const range = document.createRange();
  range.selectNodeContents(document.getElementById(id)!);
  document.getSelection()?.addRange(range);
}

describe('selectedText', () => {
  beforeEach(() => {
    document.getSelection()?.removeAllRanges();
    document.body.innerHTML = '';
  });

  it('reads the selection inside a focused text field', () => {
    document.body.innerHTML = '<input id="field" value="hello world">';
    const field = document.getElementById('field') as HTMLInputElement;
    field.focus();
    field.setSelectionRange(6, 11);
    expect(selectedText(document)).toBe('world');
  });

  it('never reads a password field', () => {
    document.body.innerHTML = '<p id="text">Visible</p><input id="field" type="password" value="secret">';
    select('text');
    (document.getElementById('field') as HTMLInputElement).focus();
    expect(selectedText(document)).toBe('');
  });

  // happy-dom upper-cases tag names even in XHTML documents; WebKit's own XHTML
  // is covered in MoteTests/XHTMLScriptTests.
  it('reads a focused field in an XHTML page, whose tag names are lower case', () => {
    document.body.innerHTML = '<input id="field" value="hello world">';
    const field = document.getElementById('field') as HTMLInputElement;
    Object.defineProperty(field, 'tagName', { value: 'input' });
    field.focus();
    field.setSelectionRange(6, 11);
    expect(selectedText(document)).toBe('world');
  });

  it('never reads a password field in an XHTML page', () => {
    document.body.innerHTML = '<p id="text">Visible</p><input id="field" type="password" value="secret">';
    select('text');
    const field = document.getElementById('field') as HTMLInputElement;
    Object.defineProperty(field, 'tagName', { value: 'input' });
    field.focus();
    expect(selectedText(document)).toBe('');
  });

  it('reads the document selection otherwise', () => {
    document.body.innerHTML = '<p id="text">Selected words</p>';
    select('text');
    expect(selectedText(document)).toBe('Selected words');
  });
});
