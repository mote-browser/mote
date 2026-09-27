// Generated from Scripts/src/popup-size.ts by `pnpm build`. Do not edit.
var motePopupSize = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/popup-size/measure.ts
/** Blink's limits for an extension popup, in CSS pixels. */
	const MIN_SIZE = 25;
	const MAX_WIDTH = 800;
	const MAX_HEIGHT = 600;
	/** Below this min-content width a page counts as very narrow, and its scroll width is used. */
	const NARROW = 100;
	/**
	* The extent a page sets for itself along one axis, or null when it sets none.
	* An extent the page sets shows as one the view doesn't have, and is remembered;
	* one equal to the view is either filling it or the extent it was given last
	* time, which the memory tells apart.
	*/
	function ownExtent(sizing, axis, measured, viewport) {
		if (Math.abs(measured - viewport) > 1) {
			sizing[axis] = measured;
			return measured;
		}
		const remembered = sizing[axis];
		if (remembered && Math.abs(remembered - viewport) <= 1) return remembered;
		return null;
	}
	/** The width a page needs: its min-content width, or its scroll width when that is very narrow. */
	function neededWidth(minContent, scrollWidth) {
		return minContent >= NARROW ? minContent : Math.max(minContent, scrollWidth);
	}
	function clampWidth(width) {
		return Math.min(800, Math.max(25, Math.ceil(width)));
	}
	function clampHeight(height) {
		return Math.min(600, Math.max(25, Math.ceil(height)));
	}
	/** Runs `measure` with `root`'s inline style overridden, then restores the page's own. */
	function withStyle(root, style, measure) {
		const saved = root.getAttribute("style");
		for (const [name, value] of Object.entries(style)) root.style.setProperty(name, value, "important");
		try {
			return measure();
		} finally {
			if (saved === null) root.removeAttribute("style");
			else root.setAttribute("style", saved);
		}
	}
	/** `neededWidth` for the page, measured with its width forced to min-content. */
	function contentWidth(root) {
		return neededWidth(withStyle(root, { width: "min-content" }, () => root.getBoundingClientRect().width), root.scrollWidth);
	}

//#endregion
//#region src/popup-size.ts
/**
	* `fit`: the popup's size, measured while the view is 25 pt square. Width: the
	* page's own width, else min-content, else the scroll width for very narrow pages.
	* Height: measured at that width.
	*
	* `grow`: the width by the same rules without the memory (a width the page sets
	* counts only when it is wider than the view), and the scroll height when the
	* page overflows, else 0. Swift only grows the popup from these.
	*
	* Returns null when there is no document yet. Inline styles are restored.
	*/
	function run(stage) {
		const root = document.documentElement;
		if (!root) return null;
		return stage === "fit" ? fit(root) : grow(root);
	}
	function fit(root) {
		const sizing = window.__moteSizing ??= {};
		const ownWidth = ownExtent(sizing, "w", root.getBoundingClientRect().width, innerWidth);
		const width = clampWidth(ownWidth ?? contentWidth(root));
		const height = withStyle(root, { width: `${width}px` }, () => {
			const measured = root.getBoundingClientRect().height;
			const ownHeight = ownExtent(sizing, "h", measured, innerHeight);
			if (ownHeight !== null) return ownHeight;
			root.style.setProperty("height", "auto", "important");
			root.style.setProperty("min-height", "0", "important");
			return root.getBoundingClientRect().height;
		});
		return [width, clampHeight(height)];
	}
	function grow(root) {
		const own = root.getBoundingClientRect().width;
		return [own > innerWidth + 1 ? own : contentWidth(root), root.scrollHeight > root.clientHeight ? root.scrollHeight : 0];
	}

//#endregion
exports.run = run;
return exports;
})({});