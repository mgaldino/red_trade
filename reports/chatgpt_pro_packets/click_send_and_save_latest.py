#!/usr/bin/env python3
"""Click the visible ChatGPT send button, wait, and save the latest assistant text."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import time

from playwright.sync_api import sync_playwright


HELPER_PATH = (
    pathlib.Path.home()
    / ".codex"
    / "skills"
    / "pro-peer-review"
    / "scripts"
    / "chatgpt_pro_review.py"
)
PROFILE = pathlib.Path.home() / ".codex" / "browser-profiles" / "chatgpt-pro-peer-review-chrome"
OUT = pathlib.Path("reports/chatgpt_pro_goal9_implementation_guide_paper_v4_20260518.md").resolve()


def load_helper():
    spec = importlib.util.spec_from_file_location("chatgpt_pro_review_helper", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load helper from {HELPER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def click_visible_send(page) -> None:
    selectors = [
        "button[data-testid='send-button']",
        "button[data-testid='composer-send-button']",
        "button[aria-label*='Send']",
        "button[aria-label*='send']",
        "button[aria-label*='Enviar']",
        "button[aria-label*='enviar']",
        "button:has-text('Send')",
        "button:has-text('Enviar')",
    ]
    last_error = None
    for selector in selectors:
        loc = page.locator(selector)
        try:
            count = loc.count()
        except Exception as exc:
            last_error = exc
            continue
        for idx in range(count - 1, -1, -1):
            try:
                button = loc.nth(idx)
                button.wait_for(state="visible", timeout=1000)
                if button.is_disabled(timeout=500):
                    continue
                button.click(timeout=3000)
                return
            except Exception as exc:
                last_error = exc

    # Last resort: click the bottom-right composer button visible in the headed viewport.
    try:
        page.mouse.click(1206, 941)
        return
    except Exception as exc:
        last_error = exc
    raise RuntimeError(f"Could not click send button: {last_error}")


def latest_assistant_text(page) -> str:
    selectors = [
        "[data-message-author-role='assistant']",
        "article[data-testid*='conversation-turn']:has([data-message-author-role='assistant'])",
        "article",
        ".markdown",
    ]
    best = ""
    for selector in selectors:
        loc = page.locator(selector)
        try:
            count = loc.count()
        except Exception:
            continue
        for idx in range(max(0, count - 4), count):
            try:
                text = loc.nth(idx).inner_text(timeout=1500).strip()
            except Exception:
                continue
            if "Goal 9 Implementation Guide" in text and len(text) > len(best):
                best = text
    return best


def wait_for_goal9(page, max_seconds: int = 1800) -> str:
    start = time.time()
    stable = 0
    previous = ""
    while time.time() - start < max_seconds:
        try:
            page.mouse.wheel(0, 5000)
        except Exception:
            pass
        text = latest_assistant_text(page)
        if text:
            if text == previous:
                stable += 1
            else:
                stable = 0
                previous = text
            if stable >= 4:
                return text
        time.sleep(5)
    return previous


def main() -> int:
    helper = load_helper()
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
        page.goto("https://chatgpt.com/c/6a0a3fe9-a6d0-83e9-9575-c17c4fa5fa3f", wait_until="domcontentloaded", timeout=60000)
        time.sleep(5)
        print("Clicking visible send button.", file=sys.stderr)
        click_visible_send(page)
        print("Waiting for Goal 9 response text.", file=sys.stderr)
        text = wait_for_goal9(page)
        if not text:
            context.close()
            raise SystemExit("Did not find a Goal 9 response.")
        OUT.write_text(helper.sanitize_markdown(text), encoding="utf-8")
        context.close()
    print(OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
