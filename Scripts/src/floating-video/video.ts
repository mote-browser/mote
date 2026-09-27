/** Marks the video that stays visible while the page floats. */
export const MARK = 'data-mote-float';

/** Set on <html> while the page floats; every rule below hangs on it. */
export const FLOATING_CLASS = 'mote-floating';

/** The <style> element holding `FLOAT_STYLE`. */
export const STYLE_ID = 'mote-float';

/**
 * Hides everything but the marked video with `visibility`, leaving the DOM intact
 * so the player keeps streaming, and stretches the video over the whole window.
 */
export const FLOAT_STYLE = [
  'html.mote-floating, html.mote-floating body {',
  'background:#000 !important; overflow:hidden !important; margin:0 !important}',
  'html.mote-floating body > * { visibility:hidden !important }',
  'html.mote-floating [data-mote-float] {',
  'visibility:visible !important; position:fixed !important;',
  'left:0 !important; top:0 !important; right:0 !important; bottom:0 !important;',
  'width:100vw !important; height:100vh !important;',
  'max-width:none !important; max-height:none !important;',
  // Players such as Netflix center the element with a translation.
  // With our top/left at zero, that moves it out of the floating window.
  'transform:none !important;',
  'object-fit:contain !important; z-index:2147483647 !important}',
  // Netflix renders timed text after the video, in a layer of its own
  // beside it or one level up. Keep it above the video without
  // exposing the rest of the player.
  'html.mote-floating [data-mote-float] ~ .player-timedtext,',
  'html.mote-floating :has(> [data-mote-float]) > .player-timedtext,',
  'html.mote-floating :has([data-mote-float]) > .player-timedtext {',
  'visibility:visible !important; z-index:2147483647 !important}',
  // Fixed or not, the video is still cut to the box of any ancestor
  // that clips — YouTube's player does — and in a window this small
  // that box sits partly or wholly off screen, more so on a page that
  // was scrolled. That was the black window.
  'html.mote-floating body :has([data-mote-float]) {',
  'overflow:visible !important}',
  // The player's own controls would sit under ours, and two sets of
  // buttons on one small window is one set too many.
  'html.mote-floating [data-mote-float]::-webkit-media-controls {',
  'display:none !important}',
].join('');

/** `HTMLMediaElement.HAVE_CURRENT_DATA`: a frame is ready to show. */
const HAVE_CURRENT_DATA = 2;

/** Whether a video is playing with a frame to show. */
export function isPlaying(video: HTMLVideoElement): boolean {
  return !video.paused && !video.ended && video.readyState >= HAVE_CURRENT_DATA;
}

/** The largest playing video; of equal ones, the last in document order. */
export function largestPlayingVideo(document: Document): HTMLVideoElement | null {
  let best: HTMLVideoElement | null = null;
  let bestArea = 0;
  for (const video of document.querySelectorAll('video')) {
    if (!isPlaying(video)) continue;
    const box = video.getBoundingClientRect();
    const area = box.width * box.height;
    // Of equal ones the last, but never one with nothing to show.
    if (area > 0 && area >= bestArea) {
      bestArea = area;
      best = video;
    }
  }
  return best;
}

/** The floating video, or else the page's first video, for the panel's controls. */
export function controlledVideo(document: Document): HTMLVideoElement | null {
  return document.querySelector<HTMLVideoElement>(`[${MARK}]`) ?? document.querySelector('video');
}

/**
 * The fraction of `video` played and whether it plays: 0 played when the length
 * is unknown or endless (a live stream), and `[0, true]` without a video.
 */
export function progress(video: HTMLVideoElement | null): [through: number, playing: boolean] {
  if (!video) return [0, true];
  const known = !!video.duration && Number.isFinite(video.duration);
  return [known ? video.currentTime / video.duration : 0, !video.paused];
}
