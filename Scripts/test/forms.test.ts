import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fillSignIn, signInFields, submittedCredentials } from '../src/forms/sign-in';
import {
  acceptsTyping,
  fieldFrame,
  holdsUnsentText,
  MAX_TYPED_FIELDS,
  TypedFields,
} from '../src/forms/typing';

// happy-dom lays nothing out: every element measures 0×0. Elements marked
// `data-hidden` stay that way; the rest get a size.
beforeEach(() => {
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (this: Element) {
    const hidden = this.hasAttribute('data-hidden');
    return new DOMRect(10, 20, hidden ? 0 : 200, hidden ? 0 : 30);
  });
});

afterEach(() => {
  vi.restoreAllMocks();
  document.body.innerHTML = '';
});

function byId<T extends HTMLElement = HTMLInputElement>(id: string): T {
  return document.getElementById(id) as T;
}

describe('signInFields', () => {
  it('finds the password and the name field before it', () => {
    document.body.innerHTML = `
      <form><input id="name" type="email"><input id="password" type="password"></form>`;
    const fields = signInFields(document);
    expect(fields?.password).toBe(byId('password'));
    expect(fields?.user).toBe(byId('name'));
  });

  it('takes the last text, email or tel field before the password', () => {
    document.body.innerHTML = `
      <form><input id="search" type="search"><input id="first" type="text">
      <input type="checkbox"><input id="phone" type="tel"><input type="hidden" value="x">
      <input id="password" type="password"><input id="after" type="text"></form>`;
    expect(signInFields(document)?.user).toBe(byId('phone'));
  });

  it('counts a field without a type as text', () => {
    document.body.innerHTML = '<form><input id="name"><input id="password" type="password"></form>';
    expect(signInFields(document)?.user).toBe(byId('name'));
  });

  it('skips password fields that take no room', () => {
    document.body.innerHTML = `
      <form><input id="decoy" type="password" data-hidden></form>
      <form><input id="name" type="text"><input id="password" type="password"></form>`;
    expect(signInFields(document)?.password).toBe(byId('password'));
  });

  it('keeps to the password field’s own form', () => {
    document.body.innerHTML = `
      <form><input id="search" type="text"></form>
      <form><input id="password" type="password"></form>`;
    const fields = signInFields(document);
    expect(fields?.password).toBe(byId('password'));
    expect(fields?.user).toBeNull();
  });

  it('searches the whole document for a password outside any form', () => {
    document.body.innerHTML = '<input id="name" type="text"><div><input id="password" type="password"></div>';
    expect(signInFields(document)?.user).toBe(byId('name'));
  });

  it('is null without a shown password field', () => {
    document.body.innerHTML = '<form><input type="text"><input type="password" data-hidden></form>';
    expect(signInFields(document)).toBeNull();
  });
});

describe('fillSignIn', () => {
  it('fills both fields as typing would, with input and change events', () => {
    document.body.innerHTML =
      '<form><input id="name" type="text"><input id="password" type="password"></form>';
    const events: string[] = [];
    for (const type of ['input', 'change'])
      document.addEventListener(type, (e) => events.push(`${type}:${(e.target as HTMLElement).id}`));

    expect(fillSignIn(signInFields(document), 'ada', 'secret')).toBe(true);
    expect(byId('name').value).toBe('ada');
    expect(byId('password').value).toBe('secret');
    expect(events).toEqual(['input:name', 'change:name', 'input:password', 'change:password']);
  });

  it('leaves a name the user already typed', () => {
    document.body.innerHTML =
      '<form><input id="name" type="text" value="grace"><input id="password" type="password"></form>';
    fillSignIn(signInFields(document), 'ada', 'secret');
    expect(byId('name').value).toBe('grace');
    expect(byId('password').value).toBe('secret');
  });

  it('fills nothing, and says so, when the sign-in is gone', () => {
    document.body.innerHTML = '<input id="name" type="text">';
    expect(fillSignIn(signInFields(document), 'ada', 'secret')).toBe(false);
    expect(byId('name').value).toBe('');
  });
});

describe('submittedCredentials', () => {
  it('is what the fields hold once a password is typed', () => {
    document.body.innerHTML =
      '<form><input id="name" type="text"><input id="password" type="password"></form>';
    byId('name').value = 'ada';
    expect(submittedCredentials(signInFields(document))).toBeNull();
    byId('password').value = 'secret';
    expect(submittedCredentials(signInFields(document))).toEqual({ user: 'ada', password: 'secret' });
  });

  it('has an empty name when the form has no name field', () => {
    document.body.innerHTML = '<form><input id="password" type="password" value="secret"></form>';
    expect(submittedCredentials(signInFields(document))).toEqual({ user: '', password: 'secret' });
  });

  it('is null without a sign-in', () => {
    expect(submittedCredentials(null)).toBeNull();
  });
});

/** Fields the user typed into, as trusted input events would record them. */
function typedInto(...elements: Element[]): TypedFields {
  const typed = new TypedFields();
  for (const element of elements) {
    const event = new Event('input');
    Object.defineProperty(event, 'isTrusted', { value: true });
    Object.defineProperty(event, 'target', { value: element });
    typed.record(event);
  }
  return typed;
}

describe('unsent text', () => {
  it('counts text typed into text fields and text areas', () => {
    document.body.innerHTML = '<input id="a" type="email"><textarea id="b"></textarea>';
    byId('a').value = 'someone@example.com';
    expect(typedInto(byId('a')).unsaved()).toBe(true);
    byId<HTMLTextAreaElement>('b').value = 'A long reply';
    expect(typedInto(byId('b')).unsaved()).toBe(true);
  });

  it('ignores search, password and emptied fields, and fields back to their default', () => {
    document.body.innerHTML = `<input id="search" type="search" value="query"><input id="pw" type="password">
      <input id="sent" type="text"><input id="same" type="text" value="default">`;
    byId('pw').value = 'secret';
    byId('sent').value = '   ';
    expect(typedInto(byId('search'), byId('pw'), byId('sent'), byId('same')).unsaved()).toBe(false);
  });

  it('forgets fields removed from the page', () => {
    document.body.innerHTML = '<textarea id="b"></textarea>';
    const area = byId<HTMLTextAreaElement>('b');
    area.value = 'Draft';
    const typed = typedInto(area);
    area.remove();
    expect(typed.unsaved()).toBe(false);
  });

  it('only records input the user made', () => {
    document.body.innerHTML = '<input id="a" type="text" value="">';
    byId('a').value = 'filled by a script';
    const typed = new TypedFields();
    byId('a').dispatchEvent(new Event('input', { bubbles: true }));
    document.addEventListener('input', (event) => typed.record(event));
    byId('a').dispatchEvent(new Event('input', { bubbles: true }));
    expect(typed.unsaved()).toBe(false);
  });

  it('remembers at most the latest fields', () => {
    document.body.innerHTML = '<textarea id="first"></textarea>';
    byId<HTMLTextAreaElement>('first').value = 'Draft';
    const others = Array.from({ length: MAX_TYPED_FIELDS }, () => document.createElement('input'));
    expect(typedInto(byId('first'), ...others).unsaved()).toBe(false);
  });

  it('reads a content-editable element by its text', () => {
    const element = { isConnected: true, tagName: 'DIV', isContentEditable: true, textContent: ' Note ' };
    expect(holdsUnsentText(element as unknown as Element)).toBe(true);
  });
});

describe('acceptsTyping', () => {
  it('is true for fields that take text at the caret', () => {
    document.body.innerHTML = `<input id="t"><input id="p" type="password"><input id="d" type="date">
      <textarea id="a"></textarea><div id="r" role="textbox"></div>`;
    for (const id of ['t', 'p', 'd', 'a', 'r']) expect(acceptsTyping(byId(id))).toBe(true);
  });

  it('is false elsewhere', () => {
    document.body.innerHTML = '<input id="c" type="checkbox"><button id="b">Go</button><p id="p">Text</p>';
    for (const id of ['c', 'b', 'p']) expect(acceptsTyping(byId(id))).toBe(false);
    expect(acceptsTyping(null)).toBe(false);
  });
});

describe('fieldFrame', () => {
  it('is the field’s frame, or null while it takes no room', () => {
    document.body.innerHTML = '<input id="shown"><input id="hidden" data-hidden>';
    expect(fieldFrame(byId('shown'))).toEqual({ x: 10, y: 20, w: 200, h: 30 });
    expect(fieldFrame(byId('hidden'))).toBeNull();
  });
});
