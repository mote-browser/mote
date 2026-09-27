import { beforeEach, describe, expect, it } from 'vitest';
import {
  bannerAround,
  buttonState,
  extensionID,
  hidePromotions,
  replaceInstallButton,
  setLabel,
  storeInstallButton,
} from '../src/web-store-bridge/store-page';

const ID = 'cjpalhdlnbpafiamejdnhcphjbkeiagm';

function byId(id: string): HTMLElement {
  return document.getElementById(id) as HTMLElement;
}

describe('extensionID', () => {
  it('reads the id from a detail page path, with or without a slug', () => {
    expect(extensionID(`/detail/ublock-origin/${ID}`)).toBe(ID);
    expect(extensionID(`/detail/${ID}`)).toBe(ID);
    expect(extensionID(`/detail/ublock-origin/${ID}/reviews`)).toBe(ID);
  });

  it('is null elsewhere or for what is not an id', () => {
    expect(extensionID('/category/extensions')).toBeNull();
    expect(extensionID('/detail/ublock-origin/short')).toBeNull();
    expect(extensionID(`/detail/x/${ID.toUpperCase()}`)).toBeNull();
    expect(extensionID(`/detail/x/${'z'.repeat(32)}`)).toBeNull();
  });

  it('is null for a longer run of letters than an id', () => {
    expect(extensionID(`/detail/x/${ID}a`)).toBeNull();
    expect(extensionID(`/detail/${ID}abcdef`)).toBeNull();
    expect(extensionID(`/detail/x/${ID}-copy`)).toBeNull();
  });
});

describe('storeInstallButton', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  it('is the disabled button mentioning Chrome, not yet handled', () => {
    document.body.innerHTML = `
      <button disabled>Share</button>
      <button disabled data-mote="theirs">Add to Chrome</button>
      <button disabled id="theirs"><span>Add to Chrome</span></button>`;
    expect(storeInstallButton(document)?.id).toBe('theirs');
  });

  it('is null without one', () => {
    document.body.innerHTML = '<button>Add to Chrome</button>';
    expect(storeInstallButton(document)).toBeNull();
  });
});

describe('bannerAround and hidePromotions', () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <header id="header">
        <div id="banner"><div id="inner"><p>Switch to Chrome?</p><button aria-label="Switch to Chrome">Go</button></div></div>
        <button disabled>Add to Chrome</button>
      </header>
      <div role="dialog" id="card"><img src="https://www.gstatic.com/images/branding/productlogos/chrome/1x.png"></div>
      <div role="dialog" id="other"><img src="https://example.com/logo.png"></div>`;
  });

  it('stops below the block holding the install button', () => {
    const button = document.querySelector('[aria-label]');
    if (!button) throw new Error('No button');
    expect(bannerAround(button)?.id).toBe('banner');
  });

  it('stops below a block with too much text', () => {
    document.body.innerHTML = `<div id="page"><p>${'x'.repeat(200)}</p><div id="banner"><button aria-label="Chrome">Go</button></div></div>`;
    const button = document.querySelector('button');
    if (!button) throw new Error('No button');
    expect(bannerAround(button)?.id).toBe('banner');
  });

  it('hides the banner and the Chrome card, and marks them', () => {
    hidePromotions(document);
    expect(byId('banner').style.display).toBe('none');
    expect(byId('banner').dataset.mote).toBe('banner');
    expect(byId('card').style.display).toBe('none');
    expect(byId('card').dataset.mote).toBe('promo');
    expect(byId('other').style.display).toBe('');
    expect(byId('header').style.display).toBe('');
  });
});

describe('replaceInstallButton', () => {
  it('hides theirs and puts an enabled copy without the store handlers after it', () => {
    document.body.innerHTML =
      '<div><button disabled jsaction="click:x" jsname="y" aria-describedby="z" class="big"><i></i>Add to Chrome</button><span></span></div>';
    const original = storeInstallButton(document);
    if (!original?.parentNode) throw new Error('No button');
    const ours = replaceInstallButton(original, original.parentNode);
    expect(original.style.display).toBe('none');
    expect(original.dataset.mote).toBe('theirs');
    expect(original.nextSibling).toBe(ours);
    expect(ours.dataset.mote).toBe('add');
    expect(ours.className).toBe('big');
    for (const name of ['disabled', 'jsaction', 'jsname', 'aria-describedby'])
      expect(ours.hasAttribute(name)).toBe(false);
  });
});

describe('buttonState', () => {
  it('shows installed, installing and available', () => {
    expect(buttonState({ installed: [ID], busy: null }, ID)).toEqual({
      label: 'Added to Mote',
      disabled: true,
    });
    expect(buttonState({ installed: [], busy: ID }, ID)).toEqual({ label: 'Adding…', disabled: true });
    expect(buttonState({ installed: ['other'], busy: 'other' }, ID)).toEqual({
      label: 'Add to Mote',
      disabled: false,
    });
    expect(buttonState({ installed: [], busy: null }, null)).toEqual({
      label: 'Add to Mote',
      disabled: false,
    });
  });
});

describe('setLabel', () => {
  it('replaces the last words and keeps the rest', () => {
    const button = document.createElement('button');
    button.innerHTML = '<i>+</i><span>Add to Chrome</span> ';
    setLabel(button, 'Add to Mote');
    expect(button.innerHTML).toBe('<i>+</i><span>Add to Mote</span> ');
  });

  it('writes the text into a button without words', () => {
    const button = document.createElement('button');
    button.innerHTML = '<i></i>';
    setLabel(button, 'Add to Mote');
    expect(button.textContent).toBe('Add to Mote');
  });
});
