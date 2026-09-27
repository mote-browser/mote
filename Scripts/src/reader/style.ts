export const READER_ID = 'mote-reader';

export const READER_STYLE = `
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
