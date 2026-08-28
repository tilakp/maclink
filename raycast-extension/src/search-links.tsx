import { existsSync } from "node:fs";
import { useState, useMemo } from "react";
import {
  Action,
  ActionPanel,
  Clipboard,
  Icon,
  List,
  Toast,
  closeMainWindow,
  open,
  showInFinder,
  showToast,
} from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { DB_PATH, LinkRow, filePathFromPayload, queryLinks } from "./db";

function iconFor(row: LinkRow): Icon {
  switch (row.resource_type) {
    case "file":
      return Icon.Document;
    case "mail":
      return Icon.Envelope;
    case "url":
      return Icon.Globe;
    default:
      return Icon.AppWindow;
  }
}

function relativeTime(unixSeconds: number): string {
  const seconds = Math.floor(Date.now() / 1000) - unixSeconds;
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months}mo ago`;
  return `${Math.floor(months / 12)}y ago`;
}

export default function SearchLinks() {
  const [searchText, setSearchText] = useState("");
  // Checked once per session, not on every keystroke. This only changes if
  // maclink has never been run at all.
  const dbExists = useMemo(() => existsSync(DB_PATH), []);

  const { data, isLoading, error } = usePromise(
    async (text: string) => (dbExists ? queryLinks(text, 100) : []),
    [searchText],
  );

  if (!dbExists) {
    return (
      <List>
        <List.EmptyView
          icon={Icon.ExclamationMark}
          title="maclink database not found"
          description={`Expected it at ${DB_PATH}. Open maclink at least once, then try again.`}
        />
      </List>
    );
  }

  return (
    <List
      isLoading={isLoading}
      onSearchTextChange={setSearchText}
      searchBarPlaceholder="Search maclink…"
      throttle
    >
      {error ? (
        <List.EmptyView
          icon={Icon.Warning}
          title="Search failed"
          description={String(error)}
        />
      ) : (
        (data ?? []).map((row) => {
          const tags = row.tags ? row.tags.split(" ").filter(Boolean) : [];
          const filePath =
            row.resource_type === "file"
              ? filePathFromPayload(row.payload)
              : null;
          const maclinkUrl = `maclink://open/${row.id}`;

          const accessories: List.Item.Accessory[] = [];
          if (row.degraded) {
            accessories.push({
              icon: Icon.ExclamationMark,
              tooltip: "Best-effort link, not a guarantee",
            });
          }
          if (tags.length > 0) {
            accessories.push({ tag: tags.join(" ") });
          }
          accessories.push({
            date: new Date(row.created_at * 1000),
            tooltip: relativeTime(row.created_at),
          });

          return (
            <List.Item
              key={row.id}
              icon={iconFor(row)}
              title={row.title}
              subtitle={row.subtitle ?? undefined}
              accessories={accessories}
              actions={
                <ActionPanel>
                  <Action
                    title="Open"
                    icon={Icon.ArrowRight}
                    onAction={async () => {
                      await open(maclinkUrl);
                      await closeMainWindow();
                    }}
                  />
                  <Action
                    title="Copy Link"
                    icon={Icon.Clipboard}
                    shortcut={{ modifiers: ["cmd"], key: "c" }}
                    onAction={async () => {
                      await Clipboard.copy(maclinkUrl);
                      await showToast({
                        style: Toast.Style.Success,
                        title: "Copied",
                        message: maclinkUrl,
                      });
                    }}
                  />
                  {filePath ? (
                    <Action
                      title="Reveal in Finder"
                      icon={Icon.Finder}
                      shortcut={{ modifiers: ["cmd"], key: "r" }}
                      onAction={async () => {
                        await showInFinder(filePath);
                      }}
                    />
                  ) : null}
                </ActionPanel>
              }
            />
          );
        })
      )}
    </List>
  );
}
