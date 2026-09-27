// WebKit serves an extension's .wasm files without the application/wasm
// type, so compiling one as it streams in fails. Most code falls back
// to fetching it whole, with a warning; some has no fallback and
// stops. The whole file is what they get from the start.

import type { Root } from './types';

/** A response for one of the extension's own files. */
export function isExtensionResponse(response: unknown): boolean {
  const r = response as { url?: unknown } | null | undefined;
  return !!r && typeof r.url === 'string' && /^(chrome|webkit)-extension:/.test(r.url);
}

export function compileWasmWhole(root: Root): void {
  if (!root.WebAssembly || typeof WebAssembly.instantiateStreaming !== 'function') return;
  const instantiate = WebAssembly.instantiateStreaming.bind(WebAssembly);
  WebAssembly.instantiateStreaming = async (source, imports) => {
    const response = await source;
    return isExtensionResponse(response)
      ? WebAssembly.instantiate(await response.arrayBuffer(), imports)
      : instantiate(response, imports);
  };
  if (typeof WebAssembly.compileStreaming === 'function') {
    const compile = WebAssembly.compileStreaming.bind(WebAssembly);
    WebAssembly.compileStreaming = async (source) => {
      const response = await source;
      return isExtensionResponse(response)
        ? WebAssembly.compile(await response.arrayBuffer())
        : compile(response);
    };
  }
}
