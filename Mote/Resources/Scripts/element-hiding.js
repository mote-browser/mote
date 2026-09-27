// Generated from Scripts/src/element-hiding.ts by `pnpm build`. Do not edit.
(function() {

//#region src/lib/element-hiding.ts
/** The <style> element hiding the elements someone chose to hide on a site. */
	const HIDDEN_ELEMENTS_STYLE_ID = "mote-hidden-elements";
	/** What each hiding rule declares. */
	const HIDDEN = { display: "none" };
	/**
	* Hides the elements `selectors` select, replacing what was hidden before: one
	* rule per selector, so one the browser can't parse leaves the others working.
	*/
	function hideElements(document, selectors) {
		return writeRules(document, HIDDEN_ELEMENTS_STYLE_ID, selectors, HIDDEN);
	}
	/**
	* Replaces the rules of the <style> element `id` — created at the end of <head>
	* when missing — with one rule per selector, declaring each of `declarations` as
	* `!important`. Returns how many selectors made a rule.
	*
	* Selectors are stored, and could say anything: never CSS text. Each is built
	* into a rule through the CSSOM, which takes exactly one rule or throws, and a
	* selector is skipped unless it parses as a selector on its own and makes a
	* style rule that declares nothing of its own — so no selector can add rules,
	* declarations or imports to the page.
	*/
	function writeRules(document, id, selectors, declarations) {
		const sheet = emptySheet(document, id);
		if (!sheet) return 0;
		let written = 0;
		for (const selector of selectors) {
			const rule = emptyRule(document, sheet, selector);
			if (!rule) continue;
			for (const [name, value] of Object.entries(declarations)) rule.style.setProperty(name, value, "important");
			written++;
		}
		return written;
	}
	/** The sheet of the <style> element `id`, emptied. */
	function emptySheet(document, id) {
		let style = document.getElementById(id);
		if (!style) {
			style = document.createElement("style");
			style.id = id;
			(document.head || document.documentElement).appendChild(style);
		}
		style.textContent = "";
		const sheet = style.sheet;
		while (sheet?.cssRules.length) sheet.deleteRule(sheet.cssRules.length - 1);
		return sheet;
	}
	/** An empty style rule for `selector` at the end of `sheet`, or null when `selector` is anything else. */
	function emptyRule(document, sheet, selector) {
		if (typeof selector !== "string" || !isSelector(document, selector)) return null;
		let index;
		try {
			index = sheet.insertRule(`${selector} {}`, sheet.cssRules.length);
		} catch {
			return null;
		}
		const rule = sheet.cssRules[index];
		const nested = rule?.cssRules?.length ?? 0;
		if (!rule || !("selectorText" in rule) || !rule.style || rule.style.length > 0 || nested > 0) {
			sheet.deleteRule(index);
			return null;
		}
		return rule;
	}
	/** Whether `selector` parses as a selector: a brace, semicolon or at-rule outside a string doesn't. */
	function isSelector(document, selector) {
		if (!selector.trim()) return false;
		try {
			document.createDocumentFragment().querySelector(selector);
			return true;
		} catch {
			return false;
		}
	}

//#endregion
//#region src/element-hiding.ts
	hideElements(document, Array.isArray(moteConfig.selectors) ? moteConfig.selectors : []);

//#endregion
})();