/** The outline drawn over the element under the pointer, with its name on a tag. */
export interface Overlay {
  frame: HTMLDivElement;
  tag: HTMLDivElement;
}

const FRAME_STYLE =
  'position:fixed;z-index:2147483646;pointer-events:none;' +
  'border:2px solid rgba(23,23,23,.9);background:rgba(23,23,23,.07);' +
  'border-radius:4px;transition:all .07s ease-out;display:none';

const TAG_STYLE =
  'position:absolute;font:500 11px -apple-system,' +
  'BlinkMacSystemFont,sans-serif;color:#fff;background:#171717;padding:2px 7px;' +
  'border-radius:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';

/** Builds the overlay, hidden, at the end of the document. */
export function createOverlay(document: Document): Overlay {
  const frame = document.createElement('div');
  frame.style.cssText = FRAME_STYLE;
  const tag = document.createElement('div');
  tag.style.cssText = TAG_STYLE;
  frame.appendChild(tag);
  document.documentElement.appendChild(frame);
  return { frame, tag };
}

/** Shows the overlay over `box`, labelled `name`, within a window `viewportWidth` wide. */
export function placeOverlay(
  { frame, tag }: Overlay,
  box: DOMRectReadOnly,
  name: string,
  viewportWidth: number,
): void {
  frame.style.display = 'block';
  frame.style.left = `${box.left}px`;
  frame.style.top = `${box.top}px`;
  frame.style.width = `${box.width}px`;
  frame.style.height = `${box.height}px`;
  tag.textContent = name;
  // Above the element if there is sky above it, tucked inside its top
  // edge if there isn't — an element flush with the top of the window
  // would otherwise have its name cut off by the window.
  tag.style.top = box.top >= 26 ? '-21px' : '3px';
  // And never off the left or right edge either.
  tag.style.left = `${Math.max(2, -box.left + 4)}px`;
  tag.style.maxWidth = `${Math.max(80, viewportWidth - Math.max(0, box.left) - 16)}px`;
}
