// Generated from Scripts/src/image-menu.ts by `pnpm build`. Do not edit.
(function() {

//#region src/image-menu/image.ts
/** Addresses Mote's image menu can open, copy and download. */
	const SUPPORTED = /^(https?|data|blob):/i;
	/**
	* The address of the image a context menu was opened on, or null when Mote's
	* menu shouldn't replace WebKit's: outside images, for broken images and 1×1
	* tracking pixels, and for any other scheme, which keeps WebKit's menu rather
	* than getting nothing.
	*/
	function menuImageAddress(target) {
		let node = target instanceof Node ? target : null;
		while (node && !(node instanceof Element && node.localName === "img")) node = node.parentElement;
		const image = node;
		if (!image || !image.currentSrc || image.naturalWidth < 2) return null;
		return SUPPORTED.test(image.currentSrc) ? image.currentSrc : null;
	}

//#endregion
//#region src/image-menu.ts
	if (!window.__moteImages) {
		window.__moteImages = true;
		document.addEventListener("contextmenu", (event) => {
			const address = menuImageAddress(event.target);
			if (!address) return;
			const handlers = window.webkit?.messageHandlers;
			if (!handlers?.moteImages) return;
			event.preventDefault();
			handlers.moteImages?.postMessage({ src: address });
		}, true);
	}

//#endregion
})();