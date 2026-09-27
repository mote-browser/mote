// Generated from Scripts/src/middle-click.ts by `pnpm build`. Do not edit.
(function() {

//#region src/middle-click/link.ts
/**
	* The address of the first link in a middle click's composed path, or null.
	*
	* The path, not the parents: a link inside an open shadow root is on it too. An
	* <area> of an image map is a link, and so is an SVG <a>, whose `href` is an
	* object that holds the address as written.
	*/
	function middleClickAddress(path) {
		for (const node of path) {
			const tag = node instanceof Element ? node.localName : "";
			if (tag !== "a" && tag !== "area") continue;
			const href = linkHref(node);
			if (href) return href;
		}
		return null;
	}
	/** An HTML link's resolved `href`, or an SVG link's resolved against the element's base. */
	function linkHref(link) {
		const href = link.href;
		if (!href || typeof href !== "object") return typeof href === "string" ? href : "";
		try {
			const written = href.baseVal;
			return written ? new URL(written, link.baseURI).href : "";
		} catch {
			return "";
		}
	}

//#endregion
//#region src/middle-click.ts
/** `MouseEvent.button` of the middle button. (In the `buttons` mask, 2 is the right button and 4 the middle.) */
	const MIDDLE_BUTTON = 1;
	if (!window.__moteMiddle) {
		window.__moteMiddle = true;
		document.addEventListener("auxclick", (event) => {
			if (event.button !== MIDDLE_BUTTON || !event.isTrusted || event.defaultPrevented) return;
			const href = middleClickAddress(event.composedPath());
			if (href) window.webkit.messageHandlers.moteMiddle?.postMessage({ href });
		});
	}

//#endregion
})();