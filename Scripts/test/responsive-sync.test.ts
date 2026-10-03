import { afterEach, describe, expect, it, vi } from 'vitest';
import { describeEvent, install, receive, setEnabled } from '../src/responsive-sync';

afterEach(() => {
  document.body.innerHTML = '';
  vi.restoreAllMocks();
  setEnabled(true);
});

describe('responsive interactions', () => {
  it('addresses the same element by id even when responsive DOM order changes', () => {
    document.body.innerHTML = '<div></div><button id="go">Go</button>';
    const button = document.getElementById('go')!;
    const event = new MouseEvent('click', { bubbles: true });
    Object.defineProperty(event, 'target', { value: button });
    expect(describeEvent(event)?.selector).toBe('#go');
    const clicked = vi.fn();
    button.addEventListener('click', clicked);
    expect(receive({ kind: 'click', selector: '#go' })).toBe(true);
    expect(clicked).toHaveBeenCalledOnce();
  });

  it('does not fall back to clicking coordinates when an element is missing', () => {
    document.body.innerHTML = '<button>Unrelated action</button>';
    const clicked = vi.fn();
    document.querySelector('button')!.addEventListener('click', clicked);
    expect(receive({ kind: 'click', selector: '#missing' })).toBe(false);
    expect(clicked).not.toHaveBeenCalled();
  });

  it('does not click an unrelated button at the same structural position', () => {
    document.body.innerHTML = '<button>Preview</button>';
    const event = new MouseEvent('click');
    Object.defineProperty(event, 'target', { value: document.querySelector('button') });
    const interaction = describeEvent(event);
    document.body.innerHTML = '<button>Delete</button>';
    const clicked = vi.fn();
    document.querySelector('button')!.addEventListener('click', clicked);
    expect(receive(interaction)).toBe(false);
    expect(clicked).not.toHaveBeenCalled();
  });

  it('copies field values through the native setter and notifies frameworks', () => {
    document.body.innerHTML = '<input id="name">';
    const input = document.querySelector('input')!;
    const seen: string[] = [];
    input.addEventListener('input', () => seen.push(input.value));
    expect(receive({ kind: 'input', selector: '#name', value: 'hello', start: 2, end: 4 })).toBe(true);
    expect(input.value).toBe('hello');
    expect(input.selectionStart).toBe(2);
    expect(input.selectionEnd).toBe(4);
    expect(seen).toEqual(['hello']);
  });

  it('never mirrors passwords, file inputs or editable content inside passwords', () => {
    document.body.innerHTML = '<input id="secret" type="password"><input id="upload" type="file">';
    for (const selector of ['#secret', '#upload']) {
      const event = new Event('input');
      Object.defineProperty(event, 'target', { value: document.querySelector(selector) });
      expect(describeEvent(event)).toBe(null);
      expect(receive({ kind: 'input', selector, value: 'secret' })).toBe(false);
    }
  });

  it('maps scroll progress across different page heights', () => {
    Object.defineProperty(document.documentElement, 'scrollHeight', { configurable: true, value: 3000 });
    Object.defineProperty(window, 'innerHeight', { configurable: true, value: 1000 });
    const scroll = vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    expect(receive({ kind: 'scroll', selector: '', x: 0, y: 0.5 })).toBe(true);
    expect(scroll).toHaveBeenCalledWith({ left: 0, top: 1000, behavior: 'instant' });
  });

  it('replays focus and keyboard listeners without typing a character twice', () => {
    document.body.innerHTML = '<input id="name" value="a">';
    const input = document.querySelector('input')!;
    const keys = vi.fn();
    input.addEventListener('keydown', keys);
    expect(receive({ kind: 'focusin', selector: '#name' })).toBe(true);
    expect(document.activeElement).toBe(input);
    expect(receive({ kind: 'keydown', selector: '#name', key: 'a', code: 'KeyA' })).toBe(true);
    expect(keys).toHaveBeenCalledOnce();
    expect(input.value).toBe('a');
  });

  it('rejects malformed events and invalid selectors without throwing', () => {
    expect(receive({ kind: 'click', selector: '[' })).toBe(false);
    expect(receive({ kind: 'scroll', selector: '', x: 0, y: Infinity })).toBe(false);
    expect(receive({ kind: 'unknown', selector: 'body' })).toBe(false);
    expect(receive(null)).toBe(false);
  });

  it('preserves input versus change semantics and leaves the receiver focus unchanged', () => {
    document.body.innerHTML = '<input id="first"><input id="second">';
    const first = document.querySelector<HTMLInputElement>('#first')!;
    const second = document.querySelector<HTMLInputElement>('#second')!;
    second.focus();
    const input = vi.fn();
    const change = vi.fn();
    first.addEventListener('input', input);
    first.addEventListener('change', change);
    receive({ kind: 'input', selector: '#first', value: 'abc' });
    expect(input).toHaveBeenCalledOnce();
    expect(change).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(second);
  });

  it('does not replay an event onto a different document', () => {
    document.body.innerHTML = '<input id="name">';
    expect(
      receive({ kind: 'input', selector: '#name', value: 'private', url: 'https://other.example/' }),
    ).toBe(false);
    expect(document.querySelector<HTMLInputElement>('input')!.value).toBe('');
  });

  it('drops queued interactions when synchronization is disabled', () => {
    document.body.innerHTML = '<input id="name">';
    setEnabled(false);
    expect(receive({ kind: 'input', selector: '#name', value: 'late' })).toBe(false);
    expect(document.querySelector<HTMLInputElement>('input')!.value).toBe('');
  });

  it('synthetic clicks and replayed focus never echo to Swift', () => {
    const post = vi.fn();
    Object.defineProperty(window, 'webkit', {
      configurable: true,
      value: { messageHandlers: { moteResponsive: { postMessage: post } } },
    });
    install();
    install();
    document.body.innerHTML = '<button id="go">Go</button>';
    document.querySelector<HTMLButtonElement>('button')!.click();
    receive({ kind: 'focusin', selector: '#go' });
    receive({ kind: 'click', selector: '#go' });
    expect(post).not.toHaveBeenCalled();
  });
});
