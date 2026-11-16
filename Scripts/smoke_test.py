#!/usr/bin/env python3
"""Checks the built app from the outside. Used by the build pipeline.

    python3 Scripts/smoke_test.py build/Panda.app [--launch]

1. Talks to panda-host exactly the way Chrome does (length-prefixed JSON on stdin/stdout)
   and checks the block / allow verdict for a list of addresses under different settings.
2. With --launch: starts the real app, checks it stays alive, sends a "tab closed" event
   through the host and checks that the app counted it in its statistics.

It temporarily replaces Panda's settings file and puts it back afterwards.
"""
import datetime
import json
import os
import shutil
import struct
import subprocess
import sys
import time

APP = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "build/Panda.app"
LAUNCH = "--launch" in sys.argv
HOST = os.path.join(APP, "Contents/MacOS/panda-host")
SUPPORT = os.path.expanduser("~/Library/Application Support/Panda")
SETTINGS = os.path.join(SUPPORT, "settings.json")
STATS = os.path.join(SUPPORT, "stats.json")

failures = []


def talk(messages, assume_running=True):
    env = dict(os.environ)
    if assume_running:
        env["PANDA_ASSUME_APP_RUNNING"] = "1"
    else:
        env.pop("PANDA_ASSUME_APP_RUNNING", None)
    proc = subprocess.Popen([HOST], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env)
    replies = []
    for message in messages:
        data = json.dumps(message).encode()
        proc.stdin.write(struct.pack("<I", len(data)) + data)
        proc.stdin.flush()
        if message.get("type") == "closed":
            continue
        header = proc.stdout.read(4)
        if len(header) < 4:
            raise RuntimeError("host closed the pipe early")
        (length,) = struct.unpack("<I", header)
        replies.append(json.loads(proc.stdout.read(length)))
    proc.stdin.close()
    proc.wait(timeout=10)
    return replies


def write_settings(**overrides):
    settings = {
        "master": True, "instagram": True, "youtube": True, "shorts": True,
        "allowNormalVideos": True, "closeDelayMs": 0,
    }
    settings.update(overrides)
    os.makedirs(SUPPORT, exist_ok=True)
    with open(SETTINGS, "w") as handle:
        json.dump(settings, handle)


def verdict(url, assume_running=True):
    reply = talk([{"type": "check", "id": 7, "url": url, "left": 0, "top": 25, "width": 1200,
                   "index": 0, "count": 3, "pinned": 0}], assume_running)[0]
    assert reply["type"] == "verdict" and reply["id"] == 7, reply
    return reply


def expect(label, url, kind, **settings):
    write_settings(**settings)
    reply = verdict(url)
    got = reply["kind"] if reply["block"] else None
    status = "ok  " if got == kind else "FAIL"
    if got != kind:
        failures.append(f"{label}: {url} -> {got}, expected {kind}")
    print(f"  {status} {label:<34} {url:<48} -> {got}")


def main():
    if not os.path.exists(HOST):
        print(f"missing {HOST}")
        return 1
    if LAUNCH and os.environ.get("CI") != "true":
        print("--launch resets Panda's statistics, so it only runs on the build server.")
        return 1

    backup = None
    if os.path.exists(SETTINGS):
        backup = SETTINGS + ".smoke-backup"
        shutil.copy2(SETTINGS, backup)

    try:
        print("Host protocol and rules")
        hello = talk([{"type": "hello"}])[0]
        assert hello["type"] == "hello" and hello["appRunning"] is True, hello

        expect("instagram home", "https://www.instagram.com/", "instagram")
        expect("instagram bare domain", "https://instagram.com/somebody", "instagram")
        expect("instagram reels", "https://www.instagram.com/reels/abc/", "instagram")
        expect("instagram direct link", "https://www.instagram.com/p/XYZ/?igsh=1", "instagram")
        expect("look-alike domain", "https://notinstagram.com/", None)
        expect("instagram as subdomain trick", "https://instagram.com.example.org/", None)
        expect("normal video", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", None)
        expect("youtube home", "https://www.youtube.com/", None)
        expect("playlist", "https://www.youtube.com/playlist?list=PL123", None)
        expect("short", "https://www.youtube.com/shorts/abcdEFGH", "shorts")
        expect("short on mobile site", "https://m.youtube.com/shorts/abcdEFGH", "shorts")
        expect("shorts tab", "https://www.youtube.com/shorts", "shorts")
        expect("channel called shortsomething", "https://www.youtube.com/shortsighted", None)
        expect("other site with /shorts/", "https://example.com/shorts/1", None)
        expect("search for the word", "https://www.google.com/search?q=instagram.com", None)

        expect("master off, instagram", "https://www.instagram.com/", None, master=False)
        expect("master off, short", "https://www.youtube.com/shorts/x", None, master=False)
        expect("instagram off", "https://www.instagram.com/", None, instagram=False)
        expect("instagram off, short still", "https://www.youtube.com/shorts/x", "shorts", instagram=False)
        expect("shorts off", "https://www.youtube.com/shorts/x", None, shorts=False)
        expect("shorts off, instagram still", "https://www.instagram.com/", "instagram", shorts=False)
        expect("youtube off", "https://www.youtube.com/shorts/x", None, youtube=False)
        expect("normal videos not allowed", "https://www.youtube.com/watch?v=1", "youtube", allowNormalVideos=False)
        expect("not allowed + youtube off", "https://www.youtube.com/watch?v=1", None,
               allowNormalVideos=False, youtube=False)

        write_settings(closeDelayMs=550)
        reply = verdict("https://www.instagram.com/")
        if reply.get("delayMs") != 550:
            failures.append(f"delay not passed through: {reply}")
        print(f"  {'ok  ' if reply.get('delayMs') == 550 else 'FAIL'} close delay passed through")

        if not LAUNCH:
            write_settings()
            reply = verdict("https://www.instagram.com/", assume_running=False)
            ok = reply["block"] is False
            if not ok:
                failures.append("blocked even though the app is not running")
            print(f"  {'ok  ' if ok else 'FAIL'} nothing blocked while the app is quit")

        if LAUNCH:
            print("Launching the app")
            if os.path.exists(STATS):
                os.remove(STATS)
            subprocess.run(["open", "-n", APP], check=True)
            time.sleep(8)
            alive = subprocess.run(["pgrep", "-x", "Panda"], capture_output=True).returncode == 0
            print(f"  {'ok  ' if alive else 'FAIL'} app is running after 8 seconds")
            if not alive:
                failures.append("app did not stay running")
            else:
                # The app rewrites settings.json at launch with its defaults (everything on).
                reply = verdict("https://www.instagram.com/", assume_running=False)
                ok = reply["block"] is True and reply["appRunning"] is True
                if not ok:
                    failures.append(f"host did not see the running app: {reply}")
                print(f"  {'ok  ' if ok else 'FAIL'} host detects the running app")

                talk([
                    {"type": "check", "id": 1, "url": "https://www.instagram.com/", "left": 0, "top": 25,
                     "width": 1200, "index": 1, "count": 3, "pinned": 0},
                    {"type": "closed", "kind": "instagram"},
                    {"type": "closed", "kind": "shorts"},
                ], assume_running=False)
                time.sleep(4)
                today = datetime.date.today().isoformat()
                counted = {}
                if os.path.exists(STATS):
                    with open(STATS) as handle:
                        counted = json.load(handle).get(today, {})
                ok = counted.get("instagram") == 1 and counted.get("shorts") == 1
                if not ok:
                    failures.append(f"app did not count the blocked tabs: {counted}")
                print(f"  {'ok  ' if ok else 'FAIL'} app counted the blocked tabs: {counted}")

                still = subprocess.run(["pgrep", "-x", "Panda"], capture_output=True).returncode == 0
                print(f"  {'ok  ' if still else 'FAIL'} app survived the catch animation")
                if not still:
                    failures.append("app crashed while handling a blocked tab")
            subprocess.run(["pkill", "-x", "Panda"])
            time.sleep(1)
    finally:
        if backup:
            shutil.move(backup, SETTINGS)

    if failures:
        print("\nFAILED")
        for failure in failures:
            print("  - " + failure)
        return 1
    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
