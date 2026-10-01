"""Render arch_setup.md into a self-contained, offline HTML guide.

Usage: python tools/build_html.py      (needs: pip install markdown)
"""
import html
import re
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "arch_setup.md"
OUT = ROOT / "arch_setup.html"
TEMPLATE = (ROOT / "tools" / "template.html").read_text(encoding="utf8")

md = markdown.Markdown(
    extensions=["fenced_code", "tables", "toc", "sane_lists"],
    extension_configs={"toc": {"permalink": False, "toc_depth": "2-3"}},
)
body = md.convert(SRC.read_text(encoding="utf8"))

# Title comes from the H1; drop it from the body (rendered in the header instead).
title_match = re.search(r"<h1[^>]*>(.*?)</h1>", body, re.S)
page_title = html.unescape(re.sub("<[^>]+>", "", title_match.group(1))) if title_match else "Arch Setup"
body = re.sub(r"<h1[^>]*>.*?</h1>\s*", "", body, count=1, flags=re.S)

# Tables scroll horizontally on narrow screens.
body = body.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")


# Code blocks: wrapper with language label + copy button.
def wrap_code(m):
    lang = m.group(1) or ""
    label = {"bash": "shell", "lua": "lua", "": "text"}.get(lang, lang)
    return (f'<div class="code"><div class="code-bar"><span>{label}</span>'
            f'<button type="button" class="copy">Copy</button></div>{m.group(0)}</div>')


body = re.sub(r'<pre><code(?: class="language-(\w+)")?>.*?</code></pre>', wrap_code, body, flags=re.S)

# External links open in a new tab.
body = re.sub(r'<a href="(https?://[^"]+)"', r'<a href="\1" target="_blank" rel="noopener"', body)


# Progress checkbox on every h2/h3 that is a real step (skip "Sources").
def add_check(m):
    tag, hid, inner = m.group(1), m.group(2), m.group(3)
    if hid == "sources":
        return m.group(0)
    return (f'<{tag} id="{hid}" class="step"><label class="done-toggle" title="Mark as done">'
            f'<input type="checkbox" data-step="{hid}"><span class="box"></span></label>'
            f'<span class="h-text">{inner}</span></{tag}>')


body = re.sub(r'<(h[23]) id="([^"]+)">(.*?)</\1>', add_check, body, flags=re.S)


# Sidebar TOC from the toc extension's tokens.
def toc_items(tokens):
    out = []
    for t in tokens:
        if t["level"] == 1:
            out.extend(toc_items(t["children"]))
            continue
        kids = toc_items(t["children"]) if t["level"] == 2 else []
        sub = f'<ol>{"".join(kids)}</ol>' if kids else ""
        name = html.escape(html.unescape(t["name"]))
        out.append(f'<li><a href="#{t["id"]}" data-target="{t["id"]}">{name}</a>{sub}</li>')
    return out


toc_html = "<ol>" + "".join(toc_items(md.toc_tokens)) + "</ol>"

page = (TEMPLATE.replace("{{TITLE}}", html.escape(page_title))
        .replace("{{TOC}}", toc_html)
        .replace("{{BODY}}", body))
OUT.write_text(page, encoding="utf8", newline="\n")
print(f"wrote {OUT} ({len(page) // 1024} KB), steps: {body.count('data-step=')}")
