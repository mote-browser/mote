// Generated from Scripts/src/favicon-probe.ts by `pnpm build`. Do not edit.
var moteFaviconProbe = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/favicon-probe/icons.ts
/** Every icon the document declares, in document order. Swift ranks them (Favicons.rank). */
	function declaredIcons(document) {
		const icons = [];
		for (const link of document.querySelectorAll("link[rel]")) {
			const rel = attribute(link, "rel");
			if (!rel.includes("icon")) continue;
			icons.push({
				href: link.href,
				rel,
				sizes: attribute(link, "sizes"),
				type: attribute(link, "type"),
				media: attribute(link, "media")
			});
		}
		return icons;
	}
	function attribute(link, name) {
		return (link.getAttribute(name) || "").toLowerCase();
	}

//#endregion
//#region src/favicon-probe.ts
	function run() {
		return declaredIcons(document);
	}

//#endregion
exports.run = run;
return exports;
})({});