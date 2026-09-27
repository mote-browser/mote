// Taken now, not looked up at each use: a sandbox that later locks
// the globals away (MetaMask's LavaMoat) would break the shim's own
// code that needs them — every fetch of a Request, every import.
// Every module of the shim takes these from here (see .oxlintrc.json).
// A worker has no DOM: the element classes are undefined there.

const root: Record<string, any> = globalThis;

export const URL: typeof globalThis.URL = root.URL;
export const FileReader: typeof globalThis.FileReader = root.FileReader;
export const Response: typeof globalThis.Response = root.Response;
export const Blob: typeof globalThis.Blob = root.Blob;
export const File: typeof globalThis.File = root.File;
export const DOMException: typeof globalThis.DOMException = root.DOMException;
export const HTMLImageElement: typeof globalThis.HTMLImageElement | undefined = root.HTMLImageElement;
export const HTMLAnchorElement: typeof globalThis.HTMLAnchorElement | undefined = root.HTMLAnchorElement;
export const Element: typeof globalThis.Element | undefined = root.Element;
export const crypto: Crypto = root.crypto;
