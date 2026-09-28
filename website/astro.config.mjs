import tailwindcss from "@tailwindcss/vite";
import { defineConfig, fontProviders } from "astro/config";

// Served by GitHub Pages at the custom domain, from the root.
export default defineConfig({
  site: "https://motebrowser.com",
  // One page, one small stylesheet: inline it and save a blocking request.
  build: { inlineStylesheets: "always" },
  vite: { plugins: [tailwindcss()] },
  // Downloaded at build time and served from the site itself, with fallback
  // metrics so nothing shifts when they arrive. No request goes to a font CDN.
  fonts: [
    {
      provider: fontProviders.fontsource(),
      name: "Geist",
      cssVariable: "--font-geist",
      weights: ["400 600"],
      styles: ["normal"],
      subsets: ["latin"],
      fallbacks: ["system-ui", "sans-serif"],
    },
    {
      provider: fontProviders.fontsource(),
      name: "Geist Mono",
      cssVariable: "--font-geist-mono",
      weights: ["400 500"],
      styles: ["normal"],
      subsets: ["latin"],
      fallbacks: ["ui-monospace", "monospace"],
    },
  ],
});
