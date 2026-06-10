#!/usr/bin/env python3
"""Collect Odoo official-doc pages into an Obsidian raw/slim baseline."""

from __future__ import annotations

import argparse
import datetime as dt
import html
import re
import sys
import time
import urllib.error
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


ODOO_APPS_URL = re.compile(r"^https://www\.odoo\.com/documentation/(?P<version>[^/]+)/applications/[^)]+\.html$")
LINK = re.compile(r"^\s*-\s*\[(?P<label>[^\]]+)\]\((?P<url>https://www\.odoo\.com/documentation/[^/]+/applications/[^)]+\.html)\)\s*$")
SECRET_VALUE = re.compile(
    r"(password|passwd|pwd|secret|authorization|client[_-]?secret|api[_-]?key|private[_ -]?key)\s*[:=]\s*\S+",
    re.IGNORECASE,
)
TOKEN_VALUE = re.compile(r"\b(token)\s*[:=]\s*(['\"]|bearer|sk-|ghp_|[A-Za-z0-9_./+=-]{24,})", re.IGNORECASE)
SAFE_DOC_VALUES = {
    "click",
    "copy",
    "enable",
    "enter",
    "generate",
    "select",
}


def fail(message: str) -> None:
    print(f"[odoo-docs-kb-collect] {message}", file=sys.stderr)
    raise SystemExit(1)


def slug_from_url(url: str) -> str:
    parsed = urlparse(url)
    match = re.match(r"^/documentation/[^/]+/applications/(?P<relative>.+)\.html$", parsed.path)
    if not match:
        fail(f"unsupported Odoo applications URL: {url}")
    relative = match.group("relative")
    return re.sub(r"[^A-Za-z0-9._-]+", "__", relative.replace("/", "__"))


def read_index_links(path: Path) -> list[tuple[str, str, str]]:
    links: list[tuple[str, str, str]] = []
    current_group = "ungrouped"
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            current_group = line[3:].strip()
            continue
        match = LINK.match(line)
        if match:
            links.append((current_group, match.group("label").strip(), match.group("url").strip()))
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[0] != "group" and not all(set(cell) <= {"-"} for cell in cells):
            url = cells[2]
            if ODOO_APPS_URL.match(url):
                links.append((cells[0] or current_group, cells[1] or slug_from_url(url), url))
    if not links:
        fail(f"no Odoo applications links found in {path}")
    duplicate_urls = sorted({url for _, _, url in links if [item[2] for item in links].count(url) > 1})
    if duplicate_urls:
        fail(f"duplicate user manual URLs in index: {duplicate_urls}")
    return links


class ArticleMarkdownParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.in_article = False
        self.depth = 0
        self.skip_depth = 0
        self.parts: list[str] = []
        self.headings: list[tuple[int, str]] = []
        self.current_heading: int | None = None
        self.heading_text: list[str] = []
        self.current_link: str | None = None
        self.link_text: list[str] = []
        self.title = ""
        self._capture_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = {key: value or "" for key, value in attrs}
        if tag == "title":
            self._capture_title = True
        if tag == "article" and attrs_map.get("id") == "o_content":
            self.in_article = True
            self.depth = 1
            return
        if not self.in_article:
            return
        self.depth += 1
        if tag in {"script", "style", "nav", "aside"}:
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            self.current_heading = int(tag[1])
            self.heading_text = []
            self.parts.append("\n\n" + "#" * self.current_heading + " ")
        elif tag in {"p", "div", "section", "article"}:
            self.parts.append("\n\n")
        elif tag == "br":
            self.parts.append("\n")
        elif tag == "li":
            self.parts.append("\n- ")
        elif tag == "pre":
            self.parts.append("\n\n```text\n")
        elif tag == "code":
            self.parts.append("`")
        elif tag == "a":
            self.current_link = attrs_map.get("href")
            self.link_text = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._capture_title = False
        if not self.in_article:
            return
        if self.skip_depth:
            if tag in {"script", "style", "nav", "aside"}:
                self.skip_depth -= 1
            return
        if tag in {"h1", "h2", "h3", "h4", "h5", "h6"} and self.current_heading:
            text = normalize_inline(" ".join(self.heading_text))
            if text:
                self.headings.append((self.current_heading, text))
            self.current_heading = None
            self.heading_text = []
            self.parts.append("\n")
        elif tag == "pre":
            self.parts.append("\n```\n")
        elif tag == "code":
            self.parts.append("`")
        elif tag == "a" and self.current_link is not None:
            text = normalize_inline(" ".join(self.link_text))
            if text and self.current_link.startswith("http"):
                self.parts.append(f" [{text}]({self.current_link}) ")
            elif text:
                self.parts.append(text)
            self.current_link = None
            self.link_text = []
        if tag == "article":
            self.depth -= 1
            if self.depth <= 0:
                self.in_article = False
            return
        if self.in_article:
            self.depth -= 1

    def handle_data(self, data: str) -> None:
        if self._capture_title:
            self.title += data
        if not self.in_article or self.skip_depth:
            return
        text = data.replace("\xa0", " ")
        if self.current_link is not None:
            self.link_text.append(text)
            return
        if self.current_heading is not None:
            self.heading_text.append(text)
        self.parts.append(text)

    def markdown(self) -> str:
        text = "".join(self.parts)
        text = html.unescape(text)
        text = re.sub(r"[ \t]+\n", "\n", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        text = re.sub(r"[ \t]{2,}", " ", text)
        return text.strip()


def normalize_inline(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


def fetch(url: str, timeout: int) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "AI_AUTO Odoo docs baseline collector"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError) as exc:
        fail(f"failed to fetch {url}: {exc}")


def parse_page(source: str, url: str) -> tuple[str, str, list[tuple[int, str]]]:
    parser = ArticleMarkdownParser()
    parser.feed(source)
    body = parser.markdown()
    if not body:
        fail(f"no article body extracted from {url}")
    title = normalize_inline(parser.title).replace(" — Odoo 19.0 documentation", "")
    if not title and parser.headings:
        title = parser.headings[0][1]
    if not title:
        fail(f"no title extracted from {url}")
    return title, body, parser.headings


def frontmatter(*, baseline_id: str, version: str, source_url: str, fetched_at: str, view: str, group: str, label: str) -> str:
    return (
        "---\n"
        f"baseline_id: {baseline_id}\n"
        f'version: "{version}"\n'
        f"tier: user\n"
        f"view: {view}\n"
        f"group: {group}\n"
        f"label: {label}\n"
        f"source_url: {source_url}\n"
        f"fetched_at: {fetched_at}\n"
        "sync_class: external_private_vault\n"
        "---\n\n"
    )


def secret_scan(path: Path) -> None:
    for line in path.read_text(encoding="utf-8").splitlines():
        if TOKEN_VALUE.search(line):
            fail(f"secret-like payload found in generated file: {path}")
        secret_match = SECRET_VALUE.search(line)
        if secret_match:
            value = secret_match.group(0).split(":", 1)[-1].split("=", 1)[-1].strip().strip("`'\"")
            first_word = re.split(r"\s+", value, maxsplit=1)[0].lower()
            if first_word in SAFE_DOC_VALUES:
                continue
        if secret_match:
            fail(f"secret-like payload found in generated file: {path}")


def render_raw(meta: str, title: str, body: str) -> str:
    return meta + f"# {title}\n\n" + body + "\n"


def render_slim(meta: str, title: str, headings: list[tuple[int, str]], source_url: str) -> str:
    lines = [
        f"# {title} - slim",
        "",
        "> Scope: navigation-only / heading-only user-manual slim view. Do not use this file as authoritative implementation text. For exact operational semantics, workflow details, or UI steps, open the matching `user-manual/raw` file or the pinned source URL.",
        "",
        f"- Source URL: {source_url}",
        "",
        "## Headings",
        "",
    ]
    if headings:
        for level, text in headings:
            indent = "  " * max(level - 1, 0)
            lines.append(f"{indent}- {'#' * level} {text}")
    else:
        lines.append("- No headings extracted.")
    return meta + "\n".join(lines) + "\n"


def rewrite_user_manual_index(
    path: Path,
    links: list[tuple[str, str, str]],
    fetched_at: str,
    *,
    baseline_id: str,
    version: str,
) -> None:
    groups: dict[str, list[tuple[str, str, str]]] = {}
    for group, label, url in links:
        groups.setdefault(group, []).append((label, url, slug_from_url(url)))
    lines = [
        "---",
        "type: technical-spec",
        f"baseline_id: {baseline_id}",
        "tier: user",
        "view: index",
        f'version: "{version}"',
        f"source_url: https://www.odoo.com/documentation/{version}/applications.html",
        f"fetched_at: {fetched_at}",
        "sync_class: external_private_vault",
        "---",
        "",
        "# Odoo 19 User Manual - Index",
        "",
        "User manual pages are mirrored as `user-manual/raw` and `user-manual/slim` according to this index. Read `user-manual/slim` for navigation, then open one matching `user-manual/raw` page when business-flow or UI-step detail matters. Studio remains excluded.",
        "",
        "| group | topic | source_url | slim | raw | status |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for group, entries in groups.items():
        for label, url, slug in entries:
            lines.append(
                f"| {group} | {label} | {url} | user-manual/slim/{slug}.md | user-manual/raw/{slug}.md | collected |"
            )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def collect(args: argparse.Namespace) -> None:
    root = args.path.resolve()
    index = root / "01_UserManual_Index.md"
    if not index.is_file():
        fail(f"missing user manual index: {index}")
    links = read_index_links(index)
    raw_dir = root / "user-manual" / "raw"
    slim_dir = root / "user-manual" / "slim"
    raw_dir.mkdir(parents=True, exist_ok=True)
    slim_dir.mkdir(parents=True, exist_ok=True)
    fetched_at = dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    for number, (group, label, url) in enumerate(links, start=1):
        slug = slug_from_url(url)
        print(f"[odoo-docs-kb-collect] {number}/{len(links)} {slug}")
        source = fetch(url, args.timeout)
        title, body, headings = parse_page(source, url)
        raw_meta = frontmatter(
            baseline_id=args.baseline_id,
            version=args.version,
            source_url=url,
            fetched_at=fetched_at,
            view="raw",
            group=group,
            label=label,
        )
        slim_meta = frontmatter(
            baseline_id=args.baseline_id,
            version=args.version,
            source_url=url,
            fetched_at=fetched_at,
            view="slim",
            group=group,
            label=label,
        )
        raw_path = raw_dir / f"{slug}.md"
        slim_path = slim_dir / f"{slug}.md"
        raw_path.write_text(render_raw(raw_meta, title, body), encoding="utf-8")
        slim_path.write_text(render_slim(slim_meta, title, headings, url), encoding="utf-8")
        secret_scan(raw_path)
        secret_scan(slim_path)
        if args.delay:
            time.sleep(args.delay)
    rewrite_user_manual_index(index, links, fetched_at, baseline_id=args.baseline_id, version=args.version)
    print(f"[odoo-docs-kb-collect] ok: {len(links)} user manual page(s)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Path to Odoo19_Docs_KB")
    parser.add_argument("--baseline-id", default="odoo-19-docs-2026-06")
    parser.add_argument("--version", default="19.0")
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--delay", type=float, default=0.0)
    args = parser.parse_args()
    collect(args)


if __name__ == "__main__":
    main()
