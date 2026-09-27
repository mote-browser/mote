/** Addresses Mote's image menu can open, copy and download. */
const SUPPORTED = /^(https?|data|blob):/i;

/**
 * The address of the image a context menu was opened on, or null when Mote's
 * menu shouldn't replace WebKit's: outside images, for broken images and 1×1
 * tracking pixels, and for any other scheme, which keeps WebKit's menu rather
 * than getting nothing.
 */
export function menuImageAddress(target: EventTarget | null): string | null {
  let node = target instanceof Node ? target : null;
  while (node && !(node instanceof Element && node.localName === 'img')) node = node.parentElement;
  const image = node as HTMLImageElement | null;
  if (!image || !image.currentSrc || image.naturalWidth < 2) return null;
  return SUPPORTED.test(image.currentSrc) ? image.currentSrc : null;
}
