# maclink for Raycast

Search your maclink links from Raycast: open them, copy the `maclink://` URL, or reveal a file link in Finder, without needing maclink's own search dropdown open.

This is a local extension, not published to the Raycast Store. `ray lint` will complain that the `author` field in `package.json` isn't a registered Raycast developer account. That check only matters for `ray publish`, and doesn't block local use.

## How it works

The `Search Links` command shells out to the `sqlite3` CLI (bundled with macOS) against maclink's own database, read-only. Nothing here talks to maclink's process directly; it just reads the same plain SQLite file maclink itself writes to, matching the approach `contrib/maclink.el` already takes for Emacs completion. See `src/db.ts` for the query, including the same `LIKE`-wildcard escaping the app itself uses (so a filename with an underscore, or a literal `%`, searches as literal text rather than as a SQL wildcard).

Actions:
- **Open** (default, Return): opens `maclink://open/<uuid>`, which routes through the running maclink app exactly like clicking the link anywhere else would.
- **Copy Link** (Cmd-C): copies the `maclink://` URL to the clipboard.
- **Reveal in Finder** (Cmd-R, file links only): reveals the file at its last known path.

## Running it

You need maclink to have run at least once, so `~/Library/Application Support/com.tilak.maclink/maclink.sqlite` exists.

```sh
cd raycast-extension
npm install
```

For day-to-day use, install it into Raycast permanently: open Raycast's preferences, go to Extensions, click the `+` button, and choose "Import Extension", pointing at this `raycast-extension` folder. That builds it once and keeps it installed without needing a terminal window open.

For active development instead, `npm run dev` (`ray develop`) starts a live-reload session that loads the extension into Raycast for as long as it keeps running.

`npm run build` (`ray build`) and `npm run lint` (`ray lint`) both work standalone if you just want to verify the extension compiles and passes lint/type-checking.
