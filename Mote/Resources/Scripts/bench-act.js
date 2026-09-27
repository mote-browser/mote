// Generated from Scripts/src/bench-act.ts by `pnpm build`. Do not edit.
var moteBenchAct = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/bench-act/actions.ts
/** Clicks, submits or (any other verb) types `text` into the element `selector` names. Returns 'ok', or why it couldn't. */
	function act(document, verb, selector, text) {
		const element = document.querySelector(selector);
		if (!element) return "nothing matches " + selector;
		element.scrollIntoView?.({
			block: "center",
			inline: "nearest"
		});
		if (verb === "click") {
			element.focus?.();
			element.click();
			return "ok";
		}
		if (verb === "submit") return submit(element, selector);
		element.focus?.();
		return typeInto(element, text, selector);
	}
	function submit(element, selector) {
		const form = element.localName === "form" ? element : element.form || element.closest("form");
		if (!form) return "no form around " + selector;
		if (form.requestSubmit) form.requestSubmit();
		else form.submit();
		return "ok";
	}
	/**
	* Types `value` into a text field or an editable element, or picks the option of
	* a <select> whose value or text it is. Local names rather than tag names, which
	* XHTML pages keep in lower case.
	*/
	function typeInto(element, value, selector) {
		if (element.isContentEditable) {
			element.textContent = value;
			element.dispatchEvent(new InputEvent("input", {
				bubbles: true,
				data: value,
				inputType: "insertText"
			}));
			return "ok";
		}
		switch (element.localName) {
			case "input":
				setValue(element, window.HTMLInputElement.prototype, value);
				return "ok";
			case "textarea":
				setValue(element, window.HTMLTextAreaElement.prototype, value);
				return "ok";
			case "select": return choose(element, value, selector);
			default: return selector + " takes no text";
		}
	}
	/**
	* Sets the value through the native setter and dispatches input and change
	* events, so frameworks that track the value (React) notice the change.
	*/
	function setValue(element, prototype, value) {
		const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
		if (setter) setter.call(element, value);
		else element.value = value;
		changed(element);
	}
	/** Selects the option whose value is `wanted`, or else whose text is, alone. */
	function choose(select, wanted, selector) {
		const options = [...select.options];
		const option = options.find((candidate) => candidate.value === wanted) ?? options.find((candidate) => candidate.text.trim() === wanted.trim());
		if (!option) return `no option ${wanted} in ${selector}`;
		for (const candidate of options) candidate.selected = candidate === option;
		changed(select);
		return "ok";
	}
	function changed(element) {
		element.dispatchEvent(new Event("input", { bubbles: true }));
		element.dispatchEvent(new Event("change", { bubbles: true }));
	}

//#endregion
//#region src/bench-act.ts
/** Returns 'ok', or why the action couldn't be done. */
	function run(verb, selector, text) {
		return act(document, verb, selector, text);
	}

//#endregion
exports.run = run;
return exports;
})({});