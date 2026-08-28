import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

// maclink deliberately keeps its database plain, queryable SQLite rather
// than shipping a companion CLI or library just for read access (see
// SPEC.md §10.3 and contrib/maclink.el, which takes the same approach).
// This path is fixed by the app's bundle identifier, independent of where
// the .app itself lives.
export const DB_PATH = join(
  homedir(),
  "Library/Application Support/com.tilak.maclink/maclink.sqlite",
);

export type ResourceType = "file" | "mail" | "url" | "generic";

export interface LinkRow {
  id: string;
  resource_type: ResourceType;
  title: string;
  subtitle: string | null;
  payload: string; // raw JSON text; shape depends on resource_type (SPEC.md §8.3)
  degraded: number; // sqlite3 -json renders booleans as 0/1
  created_at: number; // unix epoch seconds
  tags: string | null; // space-joined tag names
}

/**
 * Mirrors `LinkStore.escapedForLike` in the Swift app: backslash-escape the
 * `LIKE` metacharacters (so a filename like `report_final.pdf` or a bare
 * `%` is treated as literal text, not a wildcard), then double any single
 * quotes for safe embedding in the SQL text. The `sqlite3` CLI has no bound
 * -parameter step for a single one-shot invocation, so the pattern goes
 * directly into the query string.
 */
function escapeLikeAndQuote(raw: string): string {
  const likeEscaped = raw.replace(/[\\%_]/g, (c) => "\\" + c);
  return likeEscaped.replace(/'/g, "''");
}

const SELECT = `
  SELECT links.id, links.resource_type, links.title, links.subtitle,
         links.payload, links.degraded, links.created_at,
         GROUP_CONCAT(tags.name, ' ') AS tags
  FROM links
  LEFT JOIN link_tags ON link_tags.link_id = links.id
  LEFT JOIN tags ON tags.id = link_tags.tag_id
`;

export function queryLinks(query: string, limit = 100): LinkRow[] {
  const trimmed = query.trim();

  const sql =
    trimmed === ""
      ? `${SELECT} WHERE links.archived = 0 GROUP BY links.id ORDER BY links.created_at DESC LIMIT ${limit};`
      : (() => {
          const pattern = `%${escapeLikeAndQuote(trimmed)}%`;
          return `${SELECT}
            WHERE links.archived = 0 AND (
              links.title LIKE '${pattern}' ESCAPE '\\' OR
              links.subtitle LIKE '${pattern}' ESCAPE '\\' OR
              links.notes LIKE '${pattern}' ESCAPE '\\' OR
              links.payload LIKE '${pattern}' ESCAPE '\\' OR
              tags.name LIKE '${pattern}' ESCAPE '\\'
            )
            GROUP BY links.id
            ORDER BY links.created_at DESC
            LIMIT ${limit};`;
        })();

  const output = execFileSync("sqlite3", ["-readonly", "-json", DB_PATH, sql], {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  }).trim();

  return output === "" ? [] : (JSON.parse(output) as LinkRow[]);
}

export function filePathFromPayload(payload: string): string | null {
  try {
    const parsed = JSON.parse(payload) as { path?: string };
    return parsed.path ?? null;
  } catch {
    return null;
  }
}
