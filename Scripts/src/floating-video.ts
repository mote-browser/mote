// The page side of the floating video window: isolates the playing video while
// the web view floats, and answers the panel's controls. Called from Swift
// (FloatingVideo.swift, Browser.swift) in Mote's isolated content world, which
// reads the returned value.

import {
  controlledVideo,
  FLOAT_STYLE,
  FLOATING_CLASS,
  largestPlayingVideo,
  MARK,
  progress,
  STYLE_ID,
} from './floating-video/video';

declare global {
  interface Window {
    /** The timer that keeps the mark on a playing video while floating. */
    __moteFloatWatch?: number | null;
  }

  interface HTMLVideoElement {
    /** WebKit's own presentation modes: 'inline', 'picture-in-picture', 'fullscreen'. */
    readonly webkitPresentationMode?: string;
    webkitSetPresentationMode(mode: string): void;
  }
}

export type FloatingVideoCommand = 'on' | 'off' | 'toggle' | 'progress' | 'skip';

/**
 * `on` isolates the largest playing video ('floating', or 'none' when nothing
 * plays); `off` restores the page ('landed'); `toggle` plays or pauses and returns
 * whether it now plays; `progress` returns `[fraction played, playing]`; `skip`
 * seeks by `seconds` and returns whether there was a video.
 */
export function run(
  command: FloatingVideoCommand,
  seconds = 0,
): 'floating' | 'none' | 'landed' | boolean | [number, boolean] {
  switch (command) {
    case 'on':
      return isolate();
    case 'off':
      return restore();
    case 'toggle':
      return toggle();
    case 'progress':
      return progress(controlledVideo(document));
    case 'skip':
      return skip(seconds);
  }
}

function isolate(): 'floating' | 'none' {
  const best = largestPlayingVideo(document);
  if (!best) return 'none';

  best.setAttribute(MARK, '');
  let sheet = document.getElementById(STYLE_ID);
  if (!sheet) {
    sheet = document.createElement('style');
    sheet.id = STYLE_ID;
    (document.head || document.documentElement).appendChild(sheet);
  }
  sheet.textContent = FLOAT_STYLE;
  document.documentElement.classList.add(FLOATING_CLASS);

  // The mark has to be defended.
  //
  // Everything but the marked element is hidden, so the moment a player
  // rebuilds its DOM — and they all do, on a quality change, an ad break,
  // a React re-render — the mark goes with the old element and the window
  // turns pure black while still holding a perfectly live page. That is the
  // black rectangle, and it is not an orphaned window at all.
  //
  // So the mark is put back on whatever is playing now, four times a
  // second, for as long as the page is out.
  clearInterval(window.__moteFloatWatch ?? undefined);
  window.__moteFloatWatch = window.setInterval(() => {
    if (document.querySelector(`[${MARK}]`)) return;
    largestPlayingVideo(document)?.setAttribute(MARK, '');
  }, 250);

  return 'floating';
}

function restore(): 'landed' {
  // The engine may have put the video in its own floating window as well —
  // some players ask for that themselves. Leaving one and not the other
  // leaves you with two.
  try {
    const out = document.querySelector<HTMLVideoElement>(`video[${MARK}]`) || document.querySelector('video');
    if (out) {
      if (out.webkitPresentationMode === 'picture-in-picture') out.webkitSetPresentationMode('inline');
      // Rejects when the video has already left; there is nothing left to undo.
      if (document.pictureInPictureElement && document.exitPictureInPicture)
        document.exitPictureInPicture().catch(() => {});
    }
  } catch {
    // Presentation modes are WebKit's own; nothing to undo where they fail.
  }

  clearInterval(window.__moteFloatWatch ?? undefined);
  window.__moteFloatWatch = null;
  document.documentElement.classList.remove(FLOATING_CLASS);
  const sheet = document.getElementById(STYLE_ID);
  if (sheet) sheet.textContent = '';
  document.querySelector(`[${MARK}]`)?.removeAttribute(MARK);
  return 'landed';
}

function toggle(): boolean {
  const video = controlledVideo(document);
  if (!video) return true;
  if (video.paused) void video.play();
  else video.pause();
  return !video.paused;
}

function skip(seconds: number): boolean {
  const video = controlledVideo(document);
  if (!video) return false;
  video.currentTime = Math.max(0, video.currentTime + seconds);
  return true;
}
