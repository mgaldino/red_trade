#!/usr/bin/env python3
"""Open ChatGPT conversation and dump visible text plus a screenshot for debugging."""

from __future__ import annotations

import pathlib
import time

from playwright.sync_api import sync_playwright


PROFILE = pathlib.Path.home() / ".codex" / "browser-profiles" / "chatgpt-pro-peer-review-chrome"
OUT_DIR = pathlib.Path("reports/chatgpt_pro_packets")
URL = "https://chatgpt.com/"
PROMPT_SELECTORS = "#prompt-textarea, textarea[data-testid='prompt-textarea'], textarea, div[contenteditable='true']"


def click_if_present(page, selectors: list[str], timeout: int = 1500) -> bool:
    for selector in selectors:
        loc = page.locator(selector).first
        try:
            loc.wait_for(state="visible", timeout=timeout)
            loc.click(timeout=timeout)
            return True
        except Exception:
            continue
    return False


def open_sidebar(page) -> None:
    click_if_present(
        page,
        [
            "button[data-testid='open-sidebar-button']",
            "button[aria-label*='Open sidebar']",
            "button[aria-label*='Abrir barra lateral']",
            "button[aria-label*='sidebar']",
            "button[aria-label*='barra lateral']",
        ],
    )


def click_title(page, title: str) -> None:
    open_sidebar(page)
    time.sleep(1)
    for _ in range(5):
        for selector in [
            f"aside a:has-text('{title}')",
            f"nav a:has-text('{title}')",
            f"a[href*='/c/']:has-text('{title}')",
        ]:
            try:
                loc = page.locator(selector).first
                loc.wait_for(state="visible", timeout=1200)
                loc.click(timeout=3000)
                time.sleep(4)
                return
            except Exception:
                pass
        page.mouse.wheel(0, 900)
        time.sleep(0.5)
    raise RuntimeError(f"Could not find title: {title}")


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
    time.sleep(5)
    click_title(page, "ChatGPT Pro Review Guide")
    time.sleep(5)
    screenshot_path = OUT_DIR / "chatgpt_debug_screenshot.png"
    text_path = OUT_DIR / "chatgpt_debug_visible_text.txt"
    page.screenshot(path=str(screenshot_path), full_page=True)
    text = page.locator("body").inner_text(timeout=5000)
    prompt_count = page.locator(PROMPT_SELECTORS).count()
    more_count = page.locator("button[aria-label*='More'], button[aria-label*='Mais'], button:has-text('...')").count()
    text_path.write_text(
        f"URL: {page.url}\nPROMPT_COUNT: {prompt_count}\nMORE_COUNT: {more_count}\n\n{text}\n",
        encoding="utf-8",
    )
    print(screenshot_path)
    print(text_path)
    context.close()
