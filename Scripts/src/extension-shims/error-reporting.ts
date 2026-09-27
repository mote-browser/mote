// Errors in an extension's own pages and worker are told to the browser,
// which lists them — the only window onto a worker there is.

import type { Shim } from './types';

/** Longest error told to the browser. */
const MAX_LENGTH = 2000;

/** Console errors and warnings told in a test run, at most. */
const MAX_CONSOLE_REPORTS = 60;

/** Where an error happened: its file's path within the extension, and line. */
export function errorPlace(filename: unknown, line: unknown): string {
  return (
    String(filename || '')
      .split('/')
      .slice(3)
      .join('/') +
    ':' +
    line
  );
}

/** A console argument as text. */
export function consoleText(value: unknown): string {
  if (value instanceof Error) return value.message + ' — ' + (value.stack || '');
  try {
    return typeof value === 'string' ? value : JSON.stringify(value);
  } catch {
    return String(value);
  }
}

export function reportErrors({ root, native, config }: Shim): void {
  if (!root.addEventListener) return;
  const tell = (text: unknown): void => {
    try {
      native('debug.error', [String(text).slice(0, MAX_LENGTH)]).catch(() => {});
    } catch {}
  };
  root.addEventListener('error', (e: ErrorEvent) =>
    tell((e.message || 'error') + ' @ ' + errorPlace(e.filename, e.lineno)),
  );
  root.addEventListener('unhandledrejection', (e: PromiseRejectionEvent) =>
    tell(
      'unhandled: ' + ((e.reason && (e.reason.message || '') + ' — ' + (e.reason.stack || '')) || e.reason),
    ),
  );
  // In a test run, what the extension says went wrong, too.
  if (config.verbose && root.console) {
    let told = 0;
    for (const level of ['error', 'warn'] as const) {
      const original = console[level].bind(console);
      console[level] = (...args: unknown[]) => {
        original(...args);
        if (told++ < MAX_CONSOLE_REPORTS) tell('console.' + level + ': ' + args.map(consoleText).join(' '));
      };
    }
  }
}
