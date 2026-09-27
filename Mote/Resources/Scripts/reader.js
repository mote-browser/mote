// Generated from Scripts/src/reader.ts by `pnpm build`. Do not edit.
var moteReader = (function(exports) {

Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });
//#region src/reader/article.ts
/** Containers that may hold the article, scored by `proseScore`. */
	const CANDIDATES = "article, main, [role=\"main\"], .post, .entry, .article, .content, #content, div, section";
	/** Everything arranged around the words rather than part of them. Headers stay: the opening image often lives there. */
	const CLUTTER = "script,style,noscript,form,nav,aside,footer,button,input,select,textarea,[role=\"complementary\"],[role=\"navigation\"],[role=\"banner\"],[aria-hidden=\"true\"]";
	/** Attributes lazy-loading libraries keep the real image address in. */
	const LAZY_SOURCES = [
		"data-src",
		"data-original",
		"data-lazy-src",
		"data-lazy",
		"data-full-src",
		"data-hi-res-src",
		"data-image",
		"data-echo"
	];
	/** Video players whose embeds are part of an article; every other frame is dropped. */
	const VIDEO_PLAYERS = /youtube|youtu\.be|vimeo|dailymotion|loom\.com|streamable|wistia|ted\.com/i;
	/**
	* How much readable prose an element holds: its paragraph text, penalized by its
	* links, since navigation, related-content rails and comments are link-heavy.
	*/
	function proseScore(element) {
		const paragraphs = element.querySelectorAll("p");
		if (paragraphs.length < 2) return 0;
		let letters = 0;
		for (const paragraph of paragraphs) letters += (paragraph.innerText || "").length;
		if (letters < 400) return 0;
		const links = element.querySelectorAll("a").length;
		return letters / (1 + links * 14);
	}
	/** The element with the most prose, or null when nothing reads like an article. */
	function findArticle(document) {
		let best = null;
		let bestScore = 0;
		for (const candidate of document.querySelectorAll(CANDIDATES)) {
			const score = proseScore(candidate);
			if (score > bestScore) {
				bestScore = score;
				best = candidate;
			}
		}
		return best;
	}
	/**
	* Writes each image's real address into `src` while the original page still
	* stands: `currentSrc` is what the browser chose after srcset and <picture>, and
	* lazy loaders keep the real address in data attributes behind a placeholder.
	*/
	function resolveImages(article) {
		for (const image of article.querySelectorAll("img")) {
			image.setAttribute("loading", "eager");
			let source = image.currentSrc || image.getAttribute("src") || "";
			if (!source || source.startsWith("data:image") || image.naturalWidth <= 2) {
				const lazy = LAZY_SOURCES.map((name) => image.getAttribute(name)).find(Boolean);
				if (lazy) source = lazy;
			}
			if (source) image.setAttribute("src", source);
			const lazySet = image.getAttribute("data-srcset");
			if (lazySet && !image.getAttribute("srcset")) image.setAttribute("srcset", lazySet);
		}
	}
	/** Removes clutter, frames that aren't video players, and images with no source. */
	function cleanArticle(container) {
		for (const element of container.querySelectorAll(CLUTTER)) element.remove();
		for (const frame of container.querySelectorAll("iframe")) {
			const source = frame.getAttribute("src") || frame.getAttribute("data-src") || "";
			if (VIDEO_PLAYERS.test(source)) {
				frame.setAttribute("src", source);
				frame.removeAttribute("height");
				frame.removeAttribute("width");
			} else frame.remove();
		}
		for (const image of container.querySelectorAll("img")) {
			const source = image.getAttribute("src") || "";
			if (!source || source.startsWith("data:image")) image.remove();
		}
	}
	/** The page's own headline, or its title. */
	function articleTitle(document) {
		return document.querySelector("h1")?.innerText.trim() || document.title;
	}
	/** The host a page came from, without `www.`. */
	function siteName(host) {
		return host.replace(/^www\./, "");
	}

//#endregion
//#region src/reader/style.ts
	const READER_ID = "mote-reader";
	const READER_STYLE = `
html, body { background: #fff !important; margin: 0 !important; padding: 0 !important; }
#${READER_ID} { max-width: 38em; margin: 0 auto; padding: 72px 24px 160px;
  font: 400 18px/1.72 ui-serif, Georgia, "Times New Roman", serif; color: #171717; }
#${READER_ID} h1 { font: 600 30px/1.24 -apple-system, BlinkMacSystemFont, sans-serif;
  margin: 0 0 8px; letter-spacing: -0.01em; }
#${READER_ID} .mote-from { font: 400 12px/1 -apple-system, sans-serif; color: #a3a3a3;
  margin: 0 0 40px; text-transform: uppercase; letter-spacing: .06em; }
#${READER_ID} p { margin: 0 0 1.35em; }
#${READER_ID} img, #${READER_ID} video, #${READER_ID} iframe { max-width: 100%;
  height: auto; border-radius: 6px; margin: 1.6em 0; display: block; }
#${READER_ID} iframe { width: 100%; aspect-ratio: 16/9; height: auto; border: 0; }
#${READER_ID} figure { margin: 1.8em 0; }
#${READER_ID} figcaption { font: 400 13px/1.5 -apple-system, sans-serif; color: #a3a3a3; margin-top: .6em; }
#${READER_ID} a { color: #171717; text-underline-offset: 3px; }
#${READER_ID} h2, #${READER_ID} h3 { font: 600 20px/1.3 -apple-system, sans-serif; margin: 2em 0 .6em; }
#${READER_ID} pre, #${READER_ID} code { font-family: ui-monospace, monospace; font-size: 14px; }
#${READER_ID} pre { background: #f5f5f5; padding: 14px; border-radius: 8px; overflow: auto; }
#${READER_ID} blockquote { margin: 1.6em 0; padding-left: 1.2em; border-left: 2px solid #e8e8e8; color: #555; }
`;

//#endregion
//#region src/reader.ts
	function run() {
		const article = findArticle(document);
		if (!article) return "none";
		resolveImages(article);
		const title = articleTitle(document);
		const container = document.createElement("div");
		container.id = READER_ID;
		container.innerHTML = article.innerHTML;
		cleanArticle(container);
		const heading = document.createElement("h1");
		heading.textContent = title;
		const source = document.createElement("p");
		source.className = "mote-from";
		source.textContent = siteName(location.host);
		container.prepend(heading, source);
		const style = document.createElement("style");
		style.textContent = READER_STYLE;
		document.body.replaceChildren(container);
		document.head.append(style);
		window.scrollTo(0, 0);
		return "read";
	}

//#endregion
exports.run = run;
return exports;
})({});