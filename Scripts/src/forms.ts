// Tells Swift (FormRelay in Forms.swift) about the page's sign-in form, what it
// sends (so Mote can offer to save the password once the sign-in took), where
// the caret is, and full screen; fills a saved account when the user picks one.
//
// Injected at document end into the main frame, in Mote's isolated content
// world, so pages can't reach `window.__moteForms` or the message handler.
// Swift calls `window.__moteForms` there (Tab.swift).

import { fillSignIn, signInFields, submittedCredentials } from './forms/sign-in';
import { acceptsTyping, fieldFrame, TypedFields } from './forms/typing';

/** What Swift can ask the page, from Mote's world. */
interface FormsAPI {
  /** Whether a field typed into by hand holds text that wasn't sent. */
  unsaved(): boolean;
  /** Fills the account the user picked; false when the sign-in fields are gone. */
  fill(user: string, password: string): boolean;
  /**
   * Whether there is still a sign-in on the page. Asked after a password went
   * out, to tell a sign-in that took from one refused.
   */
  hasPassword(): boolean;
}

type FormMessage =
  | { kind: 'form' }
  | { kind: 'submit'; user: string; password: string }
  | { kind: 'settled' }
  | { kind: 'focus'; typing: boolean; rect: { x: number; y: number; w: number; h: number } | null }
  | { kind: 'fullscreen'; on: boolean };

declare global {
  interface Window {
    __moteForms?: FormsAPI;
  }
}

/** Once the sign-in fields are gone, how long they must stay gone for a sign-in done in place. */
const SETTLE_MS = 400;
/** When to look again for a sign-in the page builds itself, or the password step after the name. */
const LATE_FORM_CHECKS_MS = [700, 2200];

function post(message: FormMessage): void {
  window.webkit.messageHandlers.moteForms?.postMessage(message);
}

function findSignIn() {
  return signInFields(document);
}

/**
 * What is in the fields when they are sent. Said every time (a click on "show
 * password" says it too) because Swift only listens once the page has moved
 * on, and keeps the last thing it heard.
 */
function offer(): void {
  const sent = submittedCredentials(findSignIn());
  if (sent) post({ kind: 'submit', user: sent.user, password: sent.password });
}

/** Where the caret is, and the frame of the sign-in field it's in, which the account list hangs from. */
function caret(): void {
  const focused = document.activeElement;
  const fields = findSignIn();
  const inSignIn = fields && focused && (focused === fields.user || focused === fields.password);
  post({
    kind: 'focus',
    typing: acceptsTyping(focused),
    rect: inSignIn && focused ? fieldFrame(focused) : null,
  });
}

/**
 * Full screen, on or off, as the page hears it. Swift learns of going full
 * screen earlier from the web view itself (FormRelay.watchFullscreen): the
 * page's own requestFullscreen can't be seen from this world, and nothing
 * patched here could be without the page seeing it too.
 */
function immersed(): void {
  const webkitElement = (document as { webkitFullscreenElement?: Element | null }).webkitFullscreenElement;
  post({ kind: 'fullscreen', on: !!(document.fullscreenElement || webkitElement) });
}

if (!window.__moteForms) installForms();

function installForms(): void {
  const typed = new TypedFields();
  document.addEventListener('input', (event) => typed.record(event), true);

  window.__moteForms = {
    unsaved: () => typed.unsaved(),
    fill: (user, password) => fillSignIn(findSignIn(), user, password),
    hasPassword: () => !!findSignIn(),
  };

  document.addEventListener('submit', offer, true);
  document.addEventListener(
    'keydown',
    (event) => {
      if (event.key !== 'Enter') return;
      const fields = findSignIn();
      const focused = document.activeElement;
      if (fields && (focused === fields.password || focused === fields.user)) offer();
    },
    true,
  );
  // Plenty of sign-in buttons aren't in a form and never fire submit.
  document.addEventListener(
    'click',
    (event) => {
      const target = event.target as Element | null;
      if (!target || !target.closest) return;
      if (target.closest('button, input[type="submit"], [role="button"]')) setTimeout(offer, 0);
    },
    true,
  );

  let told = false;
  const tell = (): void => {
    if (told || !findSignIn()) return;
    told = true;
    post({ kind: 'form' });
  };
  if (document.readyState === 'complete') tell();
  else window.addEventListener('load', tell);
  for (const delay of LATE_FORM_CHECKS_MS) setTimeout(tell, delay);
  // The fields going away without a new page (a sign-in done in place) is the
  // other way a sign-in shows it took.
  let settling: ReturnType<typeof setTimeout> | undefined;
  new MutationObserver(() => {
    if (!told) {
      tell();
      return;
    }
    if (findSignIn()) return;
    told = false;
    clearTimeout(settling);
    settling = setTimeout(() => {
      if (!findSignIn()) post({ kind: 'settled' });
    }, SETTLE_MS);
  }).observe(document.documentElement, { childList: true, subtree: true });

  // The field moves when the page scrolls or the window changes size, and
  // whatever hangs from it has to move too. Once a frame at most.
  let moving = false;
  const moved = (): void => {
    if (moving) return;
    moving = true;
    requestAnimationFrame(() => {
      moving = false;
      caret();
    });
  };
  window.addEventListener('scroll', moved, true);
  window.addEventListener('resize', moved);

  document.addEventListener('fullscreenchange', immersed, true);
  document.addEventListener('webkitfullscreenchange', immersed, true);

  document.addEventListener('focusin', caret, true);
  document.addEventListener('focusout', () => setTimeout(caret, 0), true);
  document.addEventListener('mouseup', () => setTimeout(caret, 0), true);
  caret();
}
