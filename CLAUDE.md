# מלך התחזיות — notes for Claude

- Hebrew RTL PWA on GitHub Pages; backend on Supabase (SQL migrations in supabase/sql, Edge Functions in supabase/functions).
- Syntax-check: extract the inline <script> of index.html and run `node --check`; also `node --check sw.js config.js`.
- Every release: bump the cache name in sw.js (`melech-vN`).
- **Every update that players can see gets a tour**: bump `TOUR_V` in index.html, rewrite `tourNew()` ("what's new" for existing players) to describe the update, and update `TOUR_FULL` (new players / replay from settings) so it covers the new feature.
- UI text in Hebrew, masculine form. Voice files go under voice/<kind>/ with their original names and are listed in config.js.
