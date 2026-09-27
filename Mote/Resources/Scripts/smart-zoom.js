// Generated from Scripts/src/smart-zoom.ts by `pnpm build`. Do not edit.
var moteSmartZoom = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/smart-zoom/zoom.ts
/** Above this scale the page counts as zoomed in, and a double-tap zooms back out. */
	const ZOOMED_IN = 1.05;
	const MAX_SCALE = 3;
	/** Room kept on each side of the fitted block. */
	const PADDING = 12;
	/** A fit barely larger than this isn't worth it; the scale doubles instead. */
	const MIN_USEFUL_SCALE = 1.15;
	/** Back to scale 1, keeping the tapped point where it was. */
	function zoomOut(tap) {
		const pageX = tap.x / tap.scale;
		const pageY = tap.y / tap.scale;
		return {
			scale: 1,
			x: Math.max(0, tap.scrollX + pageX - tap.x),
			y: Math.max(0, tap.scrollY + pageY - tap.y)
		};
	}
	/** Fits `block` (its left edge and width in page pixels) to the view, keeping the tapped point at the same height. */
	function zoomInto(block, tap) {
		const pageY = tap.y / tap.scale;
		let scale = Math.max(1, Math.min(MAX_SCALE, tap.width / (block.width + 24)));
		if (scale < MIN_USEFUL_SCALE) scale = Math.min(MAX_SCALE, tap.scale * 2);
		return {
			scale,
			x: Math.max(0, tap.scrollX + block.left - PADDING),
			y: Math.max(0, tap.scrollY + pageY - tap.y / scale)
		};
	}
	/**
	* The innermost block around `element` wide enough to be a column of something —
	* a paragraph's column, a card, a feed — rather than the whole page's layout,
	* which is what walking up to a wide ancestor finds. Falls back to the first
	* block of a reasonable size, then to the element itself.
	*/
	function columnAround(element, viewWidth) {
		const enough = Math.max(240, viewWidth * .2);
		let best = null;
		const root = element.ownerDocument.documentElement;
		for (let node = element; node && node !== root; node = node.parentElement) {
			const rect = node.getBoundingClientRect();
			if (rect.width < 80 || rect.height < 16) continue;
			const display = getComputedStyle(node).display;
			if (display === "inline" || display === "contents") continue;
			if (!best) best = rect;
			if (rect.width >= enough) {
				best = rect;
				break;
			}
		}
		return best ?? element.getBoundingClientRect();
	}

//#endregion
//#region src/smart-zoom.ts
/**
	* `x` and `y` are the tapped point and `width` the view's width, in view points;
	* `scale` is the current page scale. Returns a `Zoom` as JSON, or null when
	* nothing is under the pointer.
	*/
	function run(x, y, scale, width) {
		const tap = {
			x,
			y,
			scale,
			width,
			scrollX: window.scrollX,
			scrollY: window.scrollY
		};
		if (scale > 1.05) return JSON.stringify(zoomOut(tap));
		const element = document.elementFromPoint(x / scale, y / scale);
		if (!element) return null;
		return JSON.stringify(zoomInto(columnAround(element, width / scale), tap));
	}

//#endregion
exports.run = run;
return exports;
})({});