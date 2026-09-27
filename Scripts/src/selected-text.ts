// Reads the selected text when the context menu opens, for "Search with…".
// Called from Swift (PageView in Tab.swift) in the default client content world;
// an empty result leaves the search to WebKit's own menu item.

import { selectedText } from './selected-text/selection';

export function run(): string {
  return selectedText(document);
}
