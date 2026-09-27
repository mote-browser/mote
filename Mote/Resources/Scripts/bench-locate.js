// Generated from Scripts/src/bench-locate.ts by `pnpm build`. Do not edit.
var moteBenchLocate = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/bench-locate/target.ts
/** Elements a `text=` selector can match: what a person would click. */
	const CLICKABLE = "button, a, [role=button], input[type=submit]";
	/**
	* The element `selector` names: a CSS selector, or `text=Label` for the button or
	* link whose text (or value) is the label, ignoring case and surrounding spaces.
	*/
	function findTarget(document, selector) {
		if (!selector.startsWith("text=")) return document.querySelector(selector);
		const wanted = selector.slice(5).trim().toLowerCase();
		const matches = (element) => {
			const { innerText, value } = element;
			return (innerText || value || "").trim().toLowerCase() === wanted;
		};
		return [...document.querySelectorAll(CLICKABLE)].find(matches) ?? null;
	}
	/** The centre of an element in viewport pixels, after scrolling it into view. */
	function centreInView(element) {
		element.scrollIntoView({
			block: "center",
			inline: "nearest"
		});
		const rect = element.getBoundingClientRect();
		return [rect.left + rect.width / 2, rect.top + rect.height / 2];
	}

//#endregion
//#region src/bench-locate.ts
/** The centre of the element `selector` names, in page points, or null when nothing matches. */
	function run(selector) {
		const element = findTarget(document, selector);
		return element ? centreInView(element) : null;
	}

//#endregion
exports.run = run;
return exports;
})({});