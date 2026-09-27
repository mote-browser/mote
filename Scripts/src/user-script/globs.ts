/**
 * A glob of chrome.userScripts' includeGlobs and excludeGlobs as a regular
 * expression for a whole URL: `*` is any run of characters, `?` any one.
 */
export function globPattern(glob: string): RegExp {
  return new RegExp(
    '^' +
      glob
        .replace(/[.+^${}()|[\]\\]/g, '\\$&')
        .replace(/\*/g, '.*')
        .replace(/\?/g, '.') +
      '$',
  );
}

/** Whether a user script runs at `href`: some include glob matches, if any are given, and no exclude glob. */
export function globsAllow(href: string, include: readonly string[], exclude: readonly string[]): boolean {
  return !(
    (include.length && !include.some((g) => globPattern(g).test(href))) ||
    exclude.some((g) => globPattern(g).test(href))
  );
}
