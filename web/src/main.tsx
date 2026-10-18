import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Docs } from "./Docs.tsx";
import "./styles.css";

const root = createRoot(document.getElementById("root")!);

// /docs is the documentation; everything else is the landing page and the room.
if (location.pathname.startsWith("/docs")) {
  root.render(
    <StrictMode>
      <Docs />
    </StrictMode>,
  );
} else {
  void (async () => {
    // Where the room server is, before the room's socket opens (net.ts reads it).
    (globalThis as { SKITTLES_SERVER?: string }).SKITTLES_SERVER = await findServer();
    const { App } = await import("./App.tsx");
    root.render(
      <StrictMode>
        <App />
      </StrictMode>,
    );
  })();
}

/// ?server=… in the link, then the config.json published next to the site (it follows the server when it moves),
/// then VITE_SKITTLES_SERVER from the build; none means this site's own origin.
async function findServer(): Promise<string | undefined> {
  const asked = new URLSearchParams(location.search).get("server");
  if (asked) return asked;
  try {
    const response = await fetch("/config.json", { cache: "no-store", signal: AbortSignal.timeout(2500) });
    if (response.ok) {
      const { server } = (await response.json()) as { server?: unknown };
      if (typeof server === "string" && /^https?:\/\//.test(server)) return server;
    }
  } catch {
    // No config: fall through.
  }
  return (import.meta.env.VITE_SKITTLES_SERVER as string | undefined) || undefined;
}
