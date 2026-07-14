#!/usr/bin/env python3
"""Download the Goal 9 guide from the existing ChatGPT conversation."""

from __future__ import annotations

import pathlib
import time

from playwright.sync_api import sync_playwright


PROFILE = pathlib.Path.home() / ".codex" / "browser-profiles" / "chatgpt-pro-peer-review-chrome"
OUT = pathlib.Path("reports/chatgpt_pro_goal9_implementation_guide_paper_v4_20260518.md").resolve()
URL = "https://chatgpt.com/c/6a0a3fe9-a6d0-83e9-9575-c17c4fa5fa3f"


def click_goal9_download(page) -> bool:
    selectors = [
        "a:has-text('Download the Markdown guide')",
        "button:has-text('Download the Markdown guide')",
        "[role='button']:has-text('Download the Markdown guide')",
        "a:has-text('Markdown guide')",
        "button:has-text('Markdown guide')",
        "[role='button']:has-text('Markdown guide')",
    ]
    for selector in selectors:
        loc = page.locator(selector)
        try:
            count = loc.count()
        except Exception:
            continue
        for idx in range(count - 1, -1, -1):
            try:
                item = loc.nth(idx)
                item.scroll_into_view_if_needed(timeout=3000)
                item.wait_for(state="visible", timeout=3000)
                with page.expect_download(timeout=30000) as download_info:
                    item.click(timeout=5000)
                download = download_info.value
                download.save_as(str(OUT))
                return OUT.exists() and OUT.stat().st_size > 0
            except Exception:
                continue
    return False


with sync_playwright() as p:
    context = p.chromium.launch_persistent_context(
        str(PROFILE),
        headless=False,
        accept_downloads=True,
        viewport={"width": 1440, "height": 1000},
        channel="chrome",
        args=["--disable-blink-features=AutomationControlled"],
    )
    page = context.pages[0] if context.pages else context.new_page()
    page.goto(URL, wait_until="domcontentloaded", timeout=60000)
    time.sleep(8)
    page.mouse.wheel(0, 12000)
    time.sleep(2)
    if not click_goal9_download(page):
        context.close()
        raise SystemExit("Could not download the Goal 9 guide link.")
    context.close()

print(OUT)
