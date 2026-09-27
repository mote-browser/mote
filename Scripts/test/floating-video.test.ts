import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { run } from '../src/floating-video';
import { controlledVideo, isPlaying, largestPlayingVideo, MARK, progress } from '../src/floating-video/video';

interface Playback {
  paused?: boolean;
  ended?: boolean;
  readyState?: number;
  width?: number;
  height?: number;
  duration?: number;
  currentTime?: number;
}

/** A video whose playback state is stubbed, since happy-dom plays nothing. */
function video(id: string, playback: Playback = {}): HTMLVideoElement {
  const element = document.createElement('video');
  element.id = id;
  const {
    paused = false,
    ended = false,
    readyState = 4,
    width = 640,
    height = 360,
    duration = NaN,
  } = playback;
  let currentTime = playback.currentTime ?? 0;
  let isPaused = paused;
  Object.defineProperties(element, {
    paused: { get: () => isPaused },
    ended: { value: ended },
    readyState: { value: readyState },
    duration: { value: duration },
    currentTime: { get: () => currentTime, set: (time: number) => (currentTime = time) },
    play: { value: () => ((isPaused = false), Promise.resolve()) },
    pause: { value: () => (isPaused = true) },
    getBoundingClientRect: { value: () => ({ width, height }) },
  });
  document.body.append(element);
  return element;
}

beforeEach(() => {
  document.body.innerHTML = '';
});

describe('isPlaying and largestPlayingVideo', () => {
  it('needs a playing video with a frame', () => {
    expect(isPlaying(video('a'))).toBe(true);
    expect(isPlaying(video('b', { paused: true }))).toBe(false);
    expect(isPlaying(video('c', { ended: true }))).toBe(false);
    expect(isPlaying(video('d', { readyState: 1 }))).toBe(false);
  });

  it('picks the largest playing video, the last of equals', () => {
    video('big-paused', { paused: true, width: 2000, height: 2000 });
    video('small', { width: 320, height: 180 });
    video('large');
    video('large-too');
    expect(largestPlayingVideo(document)?.id).toBe('large-too');
  });

  it('passes over a video with no size', () => {
    video('hidden', { width: 0, height: 0 });
    expect(largestPlayingVideo(document)).toBeNull();
    expect(run('on')).toBe('none');
    video('shown', { width: 320, height: 180 });
    video('hidden-too', { width: 0, height: 0 });
    expect(largestPlayingVideo(document)?.id).toBe('shown');
  });

  it('finds nothing when nothing plays', () => {
    video('paused', { paused: true });
    expect(largestPlayingVideo(document)).toBeNull();
  });
});

describe('controlledVideo and progress', () => {
  it('prefers the marked video over the first one', () => {
    video('first');
    video('second').setAttribute(MARK, '');
    expect(controlledVideo(document)?.id).toBe('second');
    document.getElementById('second')?.removeAttribute(MARK);
    expect(controlledVideo(document)?.id).toBe('first');
  });

  it('reports the fraction played, or 0 when unknown', () => {
    expect(progress(video('a', { duration: 200, currentTime: 50, paused: true }))).toEqual([0.25, false]);
    expect(progress(video('b', { duration: Infinity }))).toEqual([0, true]);
    expect(progress(video('c'))).toEqual([0, true]);
    expect(progress(null)).toEqual([0, true]);
  });

  it('reports a paused live stream as paused', () => {
    expect(progress(video('live', { duration: Infinity, paused: true }))).toEqual([0, false]);
    expect(progress(video('unknown', { paused: true }))).toEqual([0, false]);
  });
});

describe('run', () => {
  afterEach(() => {
    run('off');
  });

  it('isolates the playing video and restores the page', () => {
    video('player');
    expect(run('on')).toBe('floating');
    expect(document.getElementById('player')?.hasAttribute(MARK)).toBe(true);
    expect(document.documentElement.classList.contains('mote-floating')).toBe(true);
    expect(document.getElementById('mote-float')?.textContent).toContain('[data-mote-float]');

    expect(run('off')).toBe('landed');
    expect(document.getElementById('player')?.hasAttribute(MARK)).toBe(false);
    expect(document.documentElement.classList.contains('mote-floating')).toBe(false);
    expect(document.getElementById('mote-float')?.textContent).toBe('');
  });

  it('answers none when nothing plays', () => {
    video('paused', { paused: true });
    expect(run('on')).toBe('none');
    expect(document.documentElement.classList.contains('mote-floating')).toBe(false);
  });

  it('toggles playback and skips, never before the start', () => {
    const player = video('player', { currentTime: 10 });
    expect(run('toggle')).toBe(false);
    expect(run('toggle')).toBe(true);
    expect(run('skip', 15)).toBe(true);
    expect(player.currentTime).toBe(25);
    run('skip', -60);
    expect(player.currentTime).toBe(0);
  });

  it('lands even when leaving picture in picture fails', async () => {
    const unhandled: unknown[] = [];
    const listen = (reason: unknown): void => void unhandled.push(reason);
    process.on('unhandledRejection', listen);
    const player = video('player');
    Object.defineProperty(document, 'pictureInPictureElement', { value: player, configurable: true });
    Object.defineProperty(document, 'exitPictureInPicture', {
      value: () => Promise.reject(new Error('Not in picture in picture')),
      configurable: true,
    });
    try {
      run('on');
      expect(run('off')).toBe('landed');
      await new Promise((resolve) => setTimeout(resolve, 10));
      expect(unhandled).toEqual([]);
    } finally {
      process.off('unhandledRejection', listen);
      delete (document as { pictureInPictureElement?: unknown }).pictureInPictureElement;
      delete (document as { exitPictureInPicture?: unknown }).exitPictureInPicture;
    }
  });

  it('does without a video', () => {
    expect(run('toggle')).toBe(true);
    expect(run('skip', 15)).toBe(false);
    expect(run('progress')).toEqual([0, true]);
  });
});
