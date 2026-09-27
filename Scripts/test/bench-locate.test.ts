import { beforeEach, describe, expect, it } from 'vitest';
import { findTarget } from '../src/bench-locate/target';

beforeEach(() => {
  document.body.innerHTML = '';
});

describe('findTarget', () => {
  it('matches a button by its text, ignoring case and spaces', () => {
    document.body.innerHTML = '<button id="no">Cancel</button><button id="yes">  Sign In </button>';
    expect(findTarget(document, 'text=sign in')?.id).toBe('yes');
  });

  it('matches a submit input by its value', () => {
    document.body.innerHTML = '<input id="go" type="submit" value="Send">';
    expect(findTarget(document, 'text=Send')?.id).toBe('go');
  });

  it('takes anything else as a CSS selector', () => {
    document.body.innerHTML = '<p class="x">A</p>';
    expect(findTarget(document, 'p.x')?.textContent).toBe('A');
    expect(findTarget(document, 'text=missing')).toBeNull();
  });
});
