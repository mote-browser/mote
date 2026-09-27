// Lists the icons a page declares, for Swift (Favicons.swift) to pick one.
// Called in the page's content world, in the main frame.

import { type DeclaredIcon, declaredIcons } from './favicon-probe/icons';

export function run(): DeclaredIcon[] {
  return declaredIcons(document);
}
