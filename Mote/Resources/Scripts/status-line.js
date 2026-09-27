// Generated from Scripts/src/status-line.ts by `pnpm build`. Do not edit.
(function() {

//#region src/status-line/link.ts
/** Longest address sent to Swift; the status line truncates long addresses anyway. */
	const MAX_ADDRESS_LENGTH = 600;
	/**
	* The absolute address of the first link in an event's composed path, or an empty
	* string. The composed path reaches links inside open shadow trees, where the
	* event target stops at the shadow host.
	*/
	function linkAddress(path) {
		for (const node of path) {
			if (!(node instanceof Element) || node.localName !== "a" && node.localName !== "area") continue;
			const href = hrefOf(node);
			if (!href) continue;
			try {
				const address = new URL(href, node.baseURI).href;
				return address.startsWith("javascript:") ? "" : address.slice(0, 600);
			} catch {
				return "";
			}
		}
		return "";
	}
	/** An SVG link's `href` is an animated string whose value may be relative. */
	function hrefOf(link) {
		const href = link.href;
		if (typeof href === "string") return href;
		if (href instanceof SVGAnimatedString) return href.baseVal;
	}

//#endregion
//#region src/status-line.ts
	if (window.__moteLinks) window.__moteLinks.on = true;
	else {
		const state = { on: true };
		window.__moteLinks = state;
		let shown = "";
		const report = (address) => {
			if (!state.on || address === shown) return;
			shown = address;
			window.webkit.messageHandlers.link?.postMessage(address);
		};
		const options = {
			passive: true,
			capture: true
		};
		addEventListener("mouseover", (event) => report(linkAddress(event.composedPath())), options);
		addEventListener("mouseout", (event) => event.relatedTarget || report(""), options);
		addEventListener("pagehide", () => report(""));
	}

//#endregion
})();