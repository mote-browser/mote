// Generated from Scripts/src/selected-text.ts by `pnpm build`. Do not edit.
var moteSelectedText = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/selected-text/selection.ts
/**
	* The text selected in `document`: a focused text field's selection first, then
	* the document's. Same-origin frames are searched recursively; cross-origin
	* frames and password fields yield an empty string.
	*
	* Local names rather than `instanceof`, since a frame's elements come from
	* another realm; and not tag names, which XHTML pages keep in lower case.
	*/
	function selectedText(document) {
		const focused = document.activeElement;
		if (focused && (focused.localName === "iframe" || focused.localName === "frame")) try {
			const inner = focused.contentDocument;
			return inner ? selectedText(inner) : "";
		} catch {
			return "";
		}
		const isPassword = focused?.localName === "input" && focused.type === "password";
		if (focused && (focused.localName === "textarea" || focused.localName === "input" && !isPassword)) {
			const field = focused;
			try {
				const from = field.selectionStart;
				const to = field.selectionEnd;
				if (typeof from === "number" && typeof to === "number" && to > from) return field.value.slice(from, to);
			} catch {}
		}
		if (isPassword) return "";
		return document.getSelection()?.toString() ?? "";
	}

//#endregion
//#region src/selected-text.ts
	function run() {
		return selectedText(document);
	}

//#endregion
exports.run = run;
return exports;
})({});