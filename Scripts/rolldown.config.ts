import { readdirSync } from 'node:fs';
import { defineConfig, type RolldownOptions } from 'rolldown';

/**
 * Every `src/*.ts` file is a script, bundled as a self-contained IIFE into the
 * app's resources. A script that exports `run()` is exposed as `mote<Name>`
 * (reader → moteReader) for Swift to call through `callAsyncJavaScript`, which
 * keeps the name local to the call; a script without exports defines no names.
 */
const entries = readdirSync('src').filter((file) => file.endsWith('.ts') && !file.endsWith('.d.ts'));

export function globalName(entry: string): string {
  return (
    'mote' +
    entry
      .split('-')
      .map((part) => part[0]?.toUpperCase() + part.slice(1))
      .join('')
  );
}

export default defineConfig(
  entries.map((file): RolldownOptions => {
    const entry = file.replace(/\.ts$/, '');
    return {
      input: `src/${file}`,
      output: {
        file: `../Mote/Resources/Scripts/${entry}.js`,
        format: 'iife',
        name: globalName(entry),
        banner: `// Generated from Scripts/src/${file} by \`pnpm build\`. Do not edit.`,
        minify: false,
      },
    };
  }),
);
