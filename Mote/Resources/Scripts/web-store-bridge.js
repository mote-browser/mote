// Generated from Scripts/src/web-store-bridge.ts by `pnpm build`. Do not edit.
(function() {

//#region src/web-store-bridge/store-page.ts
/** Our "Add to Mote" button. */
	const OUR_BUTTON = "button[data-mote=\"add\"]";
	/** A banner taller in text than this is more than a banner: it has reached the header. */
	const MAX_BANNER_TEXT = 160;
	/** Attributes that tie the store's button to the store's own handlers, or disable it. */
	const STORE_ATTRIBUTES = [
		"disabled",
		"jsaction",
		"jscontroller",
		"jsname",
		"jslog",
		"aria-describedby"
	];
	/**
	* The extension id in a store page's path (`/detail/<slug>/<id>` or
	* `/detail/<id>`, then perhaps more of the path), or null elsewhere. This only decides what the button shows:
	* Swift installs from the tab's own URL, never from anything the page says.
	*/
	function extensionID(pathname) {
		return pathname.match(/\/detail\/(?:[^/]+\/)?([a-p]{32})(?:\/|$)/)?.[1] ?? null;
	}
	/** The store's own install button: disabled in other browsers, and mentioning Chrome. */
	function storeInstallButton(document) {
		for (const button of document.querySelectorAll("button[disabled]")) if (!button.dataset.mote && /chrome/i.test(button.textContent || "")) return button;
		return null;
	}
	/**
	* The banner around `button`: from the button up, as far as it goes without
	* taking in the header beside it — short, and holding no install button.
	*/
	function bannerAround(button) {
		let banner = null;
		let up = button.parentElement;
		while (up && up !== button.ownerDocument.body) {
			if (up.querySelector("button[disabled], button[data-mote]")) break;
			if ((up.innerText || "").length > MAX_BANNER_TEXT) break;
			banner = up;
			up = up.parentElement;
		}
		return banner;
	}
	/**
	* Hides the "Switch to Chrome" prompts: the floating card, known by the Chrome
	* logo it carries in any language — it sits right over the button — and the
	* banner around each enabled button whose label mentions Chrome.
	*/
	function hidePromotions(document) {
		for (const card of document.querySelectorAll("[role=\"dialog\"]")) if (!card.dataset.mote && card.querySelector("img[src*=\"productlogos/chrome\"]")) {
			card.style.display = "none";
			mark(card, "promo");
		}
		for (const button of document.querySelectorAll("button:not([disabled])")) {
			if (button.dataset.mote || !/chrome/i.test(button.getAttribute("aria-label") || "")) continue;
			const banner = bannerAround(button);
			if (banner && !banner.dataset.mote) {
				banner.style.display = "none";
				mark(banner, "banner");
			}
		}
	}
	/**
	* Hides the store's install button and puts a copy beside it, stripped of what
	* disables it and ties it to the store's handlers, so it keeps the store's own
	* shape and colour. Returns the copy.
	*/
	function replaceInstallButton(original, parent) {
		const ours = original.cloneNode(true);
		for (const name of STORE_ATTRIBUTES) ours.removeAttribute(name);
		mark(ours, "add");
		mark(original, "theirs");
		original.style.display = "none";
		parent.insertBefore(ours, original.nextSibling);
		return ours;
	}
	/** What our button says for the extension `id`, and whether it can be pressed. */
	function buttonState(state, id) {
		const installed = !!id && state.installed.includes(id);
		const busy = !!id && state.busy === id;
		return {
			label: installed ? "Added to Mote" : busy ? "Adding…" : "Add to Mote",
			disabled: installed || busy
		};
	}
	/** Replaces the button's last words only, so it keeps the store's icon and layout. */
	function setLabel(button, text) {
		const walker = button.ownerDocument.createTreeWalker(button, NodeFilter.SHOW_TEXT);
		let last = null;
		for (let node = walker.nextNode(); node; node = walker.nextNode()) if (node.nodeValue?.trim()) last = node;
		if (last) last.nodeValue = text;
		else button.textContent = text;
	}
	function mark(element, what) {
		element.dataset.mote = what;
	}

//#endregion
//#region src/web-store-bridge.ts
/** Waits this long after the store redraws, so a burst of changes mends once. */
	const MEND_DELAY_MS = 60;
	/** The extension this store page shows, from its own address. */
	function pageID() {
		return extensionID(location.pathname);
	}
	if (location.hostname === "chromewebstore.google.com" && !window.__moteStore) {
		let state = {
			installed: [],
			busy: null
		};
		const post = (message) => window.webkit.messageHandlers.moteStore?.postMessage(message);
		const render = (button) => {
			const { label, disabled } = buttonState(state, pageID());
			setLabel(button, label);
			button.disabled = disabled;
		};
		const renderAll = () => {
			for (const button of document.querySelectorAll(OUR_BUTTON)) render(button);
		};
		const mend = () => {
			hidePromotions(document);
			if (!pageID()) return;
			const original = storeInstallButton(document);
			if (original?.parentNode) {
				replaceInstallButton(original, original.parentNode);
				post({ placed: pageID() });
			}
			renderAll();
		};
		addEventListener("click", (event) => {
			const ours = event.target instanceof Element ? event.target.closest(OUR_BUTTON) : null;
			if (!ours) return;
			event.preventDefault();
			event.stopImmediatePropagation();
			if (!ours.disabled) post({ add: true });
		}, true);
		window.__moteStore = { state(next) {
			state = next || state;
			renderAll();
		} };
		let queued = false;
		new MutationObserver(() => {
			if (queued) return;
			queued = true;
			setTimeout(() => {
				queued = false;
				mend();
			}, MEND_DELAY_MS);
		}).observe(document.documentElement, {
			childList: true,
			subtree: true
		});
		mend();
	}

//#endregion
})();