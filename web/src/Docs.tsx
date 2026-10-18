// The documentation at /docs. The text lives in docs/guide/en.md and docs/guide/ka.md (readable on GitHub too) and is
// split into pages at <!-- page: id; group: name --> markers. Layout: page list, article, and the page's sections.

import { marked } from "marked";
import { useEffect, useMemo, useState } from "react";
import en from "../../docs/guide/en.md?raw";
import ka from "../../docs/guide/ka.md?raw";
import { BrandMark, REPO } from "./Landing.tsx";

type Lang = "en" | "ka";
type Section = { id: string; title: string };
type Page = { id: string; group: string; title: string; html: string; sections: Section[] };

const SOURCES: Record<Lang, string> = { en, ka };
const UI: Record<Lang, { home: string; open: string; onPage: string; prev: string; next: string; pages: string }> = {
  en: { home: "Home", open: "Open the room", onPage: "On this page", prev: "Previous", next: "Next", pages: "Pages" },
  ka: { home: "მთავარი", open: "ოთახის გახსნა", onPage: "ამ გვერდზე", prev: "წინა", next: "შემდეგი", pages: "გვერდები" },
};

const plain = (html: string): string => html.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&#39;/g, "'").replace(/&quot;/g, '"');

function parse(source: string): Page[] {
  const markers = [...source.matchAll(/<!--\s*page:\s*([\w-]+)(?:;\s*group:\s*(.+?))?\s*-->/g)];
  let group = "";
  return markers.map((m, i) => {
    if (m[2]) group = m[2].trim();
    const body = source.slice(m.index! + m[0].length, markers[i + 1]?.index ?? source.length).trim();
    const title = body.match(/^# (.+)$/m)?.[1] ?? m[1]!;
    const sections: Section[] = [];
    // Section headings get ids, so "On this page" can jump to them.
    const html = (marked.parse(body.replace(/^# .+$/m, ""), { async: false }) as string).replace(/<h2>(.*?)<\/h2>/g, (_, inner: string) => {
      const id = `${m[1]}-${sections.length + 1}`;
      sections.push({ id, title: plain(inner) });
      return `<h2 id="${id}">${inner}</h2>`;
    });
    return { id: m[1]!, group, title, html, sections };
  });
}

function initialLang(): Lang {
  const asked = new URLSearchParams(location.search).get("lang");
  if (asked === "en" || asked === "ka") return asked;
  try {
    return localStorage.getItem("skittles-docs-lang") === "ka" ? "ka" : "en";
  } catch {
    return "en";
  }
}

const pageFromPath = (): string => location.pathname.split("/")[2] ?? "";

export function Docs() {
  const [lang, setLang] = useState<Lang>(initialLang);
  const pages = useMemo(() => parse(SOURCES[lang]), [lang]);
  const [id, setId] = useState(pageFromPath);
  const index = Math.max(0, pages.findIndex((p) => p.id === id));
  const page = pages[index]!;
  const groups = [...new Set(pages.map((p) => p.group))];
  const t = UI[lang];

  useEffect(() => {
    const onPop = () => setId(pageFromPath());
    addEventListener("popstate", onPop);
    return () => removeEventListener("popstate", onPop);
  }, []);
  useEffect(() => {
    document.title = `${page.title} · Skittles docs`;
    document.documentElement.lang = lang;
  }, [page, lang]);

  const go = (next: string) => {
    history.pushState(null, "", `/docs/${next}${location.search}`);
    setId(next);
    scrollTo({ top: 0 });
  };
  const pick = (next: Lang) => {
    setLang(next);
    try {
      localStorage.setItem("skittles-docs-lang", next);
    } catch {
      // Private windows may refuse storage; the choice still holds for this visit.
    }
  };
  const link = (p: Page) => (
    <a
      key={p.id}
      href={`/docs/${p.id}`}
      className={p.id === page.id ? "on" : ""}
      onClick={(e) => {
        e.preventDefault();
        go(p.id);
      }}
    >
      {p.title}
    </a>
  );
  const prev = pages[index - 1];
  const next = pages[index + 1];

  return (
    <div className="docs dark">
      <header className="site-header">
        <a className="site-brand" href="/">
          <BrandMark size={22} />
          Skittles
        </a>
        <span className="docs-tag">Docs</span>
        <nav>
          <a href="/">{t.home}</a>
          <a href={REPO} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </nav>
        <div className="lang" role="group" aria-label="Language">
          <button className={lang === "en" ? "on" : ""} onClick={() => pick("en")}>
            EN
          </button>
          <button className={lang === "ka" ? "on" : ""} onClick={() => pick("ka")}>
            ქარ
          </button>
        </div>
        <button onClick={() => (location.href = "/")}>{t.open}</button>
      </header>

      <div className="docs-body">
        <aside className="docs-nav">
          {groups.map((g) => (
            <div key={g}>
              <h4>{g}</h4>
              {pages.filter((p) => p.group === g).map(link)}
            </div>
          ))}
        </aside>

        <main className="docs-main">
          <select className="docs-picker" aria-label={t.pages} value={page.id} onChange={(e) => go(e.target.value)}>
            {groups.map((g) => (
              <optgroup key={g} label={g}>
                {pages
                  .filter((p) => p.group === g)
                  .map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.title}
                    </option>
                  ))}
              </optgroup>
            ))}
          </select>
          <div className="docs-crumb">{page.group}</div>
          <h1>{page.title}</h1>
          <article className="prose" dangerouslySetInnerHTML={{ __html: page.html }} />
          <nav className="docs-pager">
            {prev ? (
              <a href={`/docs/${prev.id}`} onClick={(e) => (e.preventDefault(), go(prev.id))}>
                <small>← {t.prev}</small>
                {prev.title}
              </a>
            ) : (
              <span />
            )}
            {next && (
              <a className="next" href={`/docs/${next.id}`} onClick={(e) => (e.preventDefault(), go(next.id))}>
                <small>{t.next} →</small>
                {next.title}
              </a>
            )}
          </nav>
        </main>

        <aside className="docs-toc">
          {page.sections.length > 0 && <h4>{t.onPage}</h4>}
          {page.sections.map((s) => (
            <a
              key={s.id}
              href={`#${s.id}`}
              onClick={(e) => {
                e.preventDefault();
                document.getElementById(s.id)?.scrollIntoView({ behavior: "smooth" });
              }}
            >
              {s.title}
            </a>
          ))}
        </aside>
      </div>
    </div>
  );
}
