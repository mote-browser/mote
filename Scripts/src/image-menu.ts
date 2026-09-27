// Replaces WebKit's context menu on images with Mote's own (ImageMenu.swift),
// whose Copy and Download work. Injected at document start into every frame, in
// Mote's isolated content world.

import { menuImageAddress } from './image-menu/image';

declare global {
  interface Window {
    __moteImages?: boolean;
  }
}

if (!window.__moteImages) {
  window.__moteImages = true;
  document.addEventListener(
    'contextmenu',
    (event) => {
      const address = menuImageAddress(event.target);
      if (!address) return;
      // WebKit's own menu only steps aside when there is a way to ask for this
      // one — otherwise a right-click shows nothing at all.
      const handlers = window.webkit?.messageHandlers;
      if (!handlers?.moteImages) return;
      event.preventDefault();
      handlers.moteImages?.postMessage({ src: address });
    },
    true,
  );
}
