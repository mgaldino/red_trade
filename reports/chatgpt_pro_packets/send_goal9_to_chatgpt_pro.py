#!/usr/bin/env python3
"""Send the Goal 9 packet to a titled ChatGPT conversation.

This wrapper reuses the local pro-peer-review helper but selects the existing
conversation by title before uploading the packet and attachments.
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import sys
import time


HELPER_PATH = (
    pathlib.Path.home()
    / ".codex"
    / "skills"
    / "pro-peer-review"
    / "scripts"
    / "chatgpt_pro_review.py"
)


def load_helper():
    spec = importlib.util.spec_from_file_location("chatgpt_pro_review_helper", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load helper from {HELPER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def open_sidebar(helper, page) -> None:
    helper.click_if_present(
        page,
        [
            "button[data-testid='open-sidebar-button']",
            "button[aria-label*='Open sidebar']",
            "button[aria-label*='Abrir barra lateral']",
            "button[aria-label*='sidebar']",
            "button[aria-label*='barra lateral']",
        ],
        timeout=2500,
    )
    time.sleep(1)


def wait_for_any_prompt(helper, context, page, login_wait: int):
    deadline = time.time() + login_wait
    selectors = [
        "#prompt-textarea",
        "textarea[data-testid='prompt-textarea']",
        "textarea",
        "div[contenteditable='true']",
    ]
    last_url = ""
    while time.time() < deadline:
        pages = context.pages or [page]
        for candidate in pages:
            for selector in selectors:
                loc = candidate.locator(selector)
                try:
                    count = loc.count()
                except Exception:
                    continue
                for idx in range(count):
                    try:
                        loc.nth(idx).wait_for(state="visible", timeout=800)
                        return candidate
                    except Exception:
                        continue
        try:
            urls = " | ".join(candidate.url for candidate in pages)
        except Exception:
            urls = ""
        if urls != last_url:
            print(f"Waiting for any visible ChatGPT prompt: {urls}", file=sys.stderr)
            last_url = urls
        time.sleep(2)
    raise RuntimeError(f"No visible ChatGPT prompt box became available within {login_wait} seconds.")


def click_conversation_by_title(helper, page, title: str, fallback_index: int | None) -> None:
    open_sidebar(helper, page)

    title_selectors = [
        f"aside a:has-text('{title}')",
        f"nav a:has-text('{title}')",
        f"[data-testid*='history'] a:has-text('{title}')",
        f"a[href*='/c/']:has-text('{title}')",
    ]
    last_error = None
    for _ in range(3):
        for selector in title_selectors:
            loc = page.locator(selector).first
            try:
                loc.wait_for(state="visible", timeout=2500)
                loc.click(timeout=5000)
                try:
                    page.wait_for_load_state("domcontentloaded", timeout=15000)
                except Exception:
                    pass
                time.sleep(3)
                return
            except Exception as exc:
                last_error = exc
        try:
            page.mouse.wheel(0, 900)
        except Exception:
            pass
        time.sleep(1)

    if fallback_index is not None:
        selectors = [
            "aside a[href*='/c/']",
            "nav a[href*='/c/']",
            "[data-testid*='history'] a[href*='/c/']",
            "a[href*='/c/']",
        ]
        for selector in selectors:
            loc = page.locator(selector)
            try:
                count = loc.count()
            except Exception as exc:
                last_error = exc
                continue
            if count > fallback_index:
                try:
                    item = loc.nth(fallback_index)
                    text = item.inner_text(timeout=1500).strip()
                    print(f"Falling back to conversation index {fallback_index}: {text}", file=sys.stderr)
                    item.click(timeout=5000)
                    try:
                        page.wait_for_load_state("domcontentloaded", timeout=15000)
                    except Exception:
                        pass
                    time.sleep(3)
                    return
                except Exception as exc:
                    last_error = exc

    raise RuntimeError(f"Could not open conversation titled {title!r}: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packet", type=pathlib.Path)
    parser.add_argument("--conversation-title", default="ChatGPT Pro Review Guide")
    parser.add_argument("--fallback-index", type=int, default=2, help="0-based visible sidebar conversation index.")
    parser.add_argument("--paper", type=pathlib.Path)
    parser.add_argument("--attachment", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument(
        "--profile-dir",
        type=pathlib.Path,
        default=pathlib.Path.home() / ".codex" / "browser-profiles" / "chatgpt-pro-peer-review-chrome",
    )
    parser.add_argument("--browser-channel", default="chrome")
    parser.add_argument("--headed", action="store_true")
    parser.add_argument("--login-wait", type=int, default=900)
    parser.add_argument("--response-wait", type=int, default=1800)
    args = parser.parse_args()

    helper = load_helper()
    packet = args.packet.resolve()
    if not packet.exists():
        raise SystemExit(f"Packet not found: {packet}")
    attachments = []
    if args.paper:
        attachments.append(args.paper)
    attachments.extend(args.attachment)
    for attachment in attachments:
        if not attachment.exists():
            raise SystemExit(f"Attachment not found: {attachment}")

    try:
        from playwright.sync_api import sync_playwright  # type: ignore
    except ImportError as exc:
        raise SystemExit("Playwright is not installed in this Python environment.") from exc

    prompt = packet.read_text(encoding="utf-8")
    out = args.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    profile = args.profile_dir.resolve()
    profile.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        launch_kwargs = {
            "headless": not args.headed,
            "accept_downloads": True,
            "viewport": {"width": 1440, "height": 1000},
            "args": ["--disable-blink-features=AutomationControlled"],
        }
        if args.browser_channel != "chromium":
            launch_kwargs["channel"] = args.browser_channel
        context = p.chromium.launch_persistent_context(str(profile), **launch_kwargs)
        context.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined});")
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(helper.CHATGPT_URL, wait_until="domcontentloaded", timeout=60000)

        print(f"Complete login/Cloudflare in the opened browser if needed. Waiting up to {args.login_wait} seconds.", file=sys.stderr)
        page = wait_for_any_prompt(helper, context, page, args.login_wait)

        print(f"Opening conversation titled: {args.conversation_title}", file=sys.stderr)
        click_conversation_by_title(helper, page, args.conversation_title, args.fallback_index)
        page = wait_for_any_prompt(helper, context, page, args.login_wait)

        print(f"Uploading {len(attachments)} attachment(s).", file=sys.stderr)
        upload_results = helper.upload_files(page, [attachment.resolve() for attachment in attachments])
        for attachment, uploaded in upload_results.items():
            if not uploaded:
                print(f"Could not attach {attachment}; sending packet text anyway.", file=sys.stderr)

        print("Sending Goal 9 packet to ChatGPT.", file=sys.stderr)
        helper.set_prompt(page, prompt)
        helper.click_send(page)
        completion = helper.wait_for_completion(page, min_seconds=30, max_seconds=args.response_wait, out=out)

        if completion != "downloaded" and not helper.try_download_markdown(page, out):
            text = helper.find_latest_assistant_text(page)
            if not text:
                context.close()
                raise SystemExit("Could not locate an assistant response to save.")
            out.write_text(helper.sanitize_markdown(text), encoding="utf-8")
            print(f"Saved assistant response text to {out}", file=sys.stderr)

        context.close()

    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
