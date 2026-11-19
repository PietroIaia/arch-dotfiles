#!/usr/bin/python3.14
# Usage: tween-text.py <interval-s> <shell-command>
# Polls the command and, when its output changes, emits frames easing the text length from old to new.
import os
import select
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True  # keep lib/__pycache__ out of the config repo
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from anim import ANIM_MS, FRAME_MS, ease  # noqa: E402

TIMEOUT = 5
running: subprocess.Popen[str] | None = None  # in its own session, so a SIGTERM to us must take it down too


def frame(old: str, new: str, n: int) -> str:
    # Growing reveals the new text; shrinking cuts the old one down to the new length first.
    return new[:n] if len(new) >= len(old) else (old[:n] if n > len(new) else new)


def read(cmd: str) -> str | None:
    # None on timeout, so a stalled command keeps the shown value.
    global running
    with subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, errors="replace", start_new_session=True) as proc:
        running = proc
        try:
            out, _ = proc.communicate(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            return None
        finally:
            running = None
    # eww blanks any label whose text holds a backslash.
    return out.strip().splitlines()[0].replace("\\", "∖") if out.strip() else ""


def emit(text: str) -> None:
    try:
        print(text, flush=True)
    except BrokenPipeError:
        os._exit(0)


def wait(seconds: float, watch: select.poll) -> None:
    # Sleeps, exiting at once if eww closes our stdout.
    if watch.poll(seconds * 1000):
        os._exit(0)


def on_term(*_: object) -> None:
    if running is not None:
        os.killpg(running.pid, signal.SIGKILL)
    os._exit(0)


def main() -> int:
    interval, cmd = float(sys.argv[1]), sys.argv[2]
    signal.signal(signal.SIGTERM, on_term)
    watch = select.poll()
    watch.register(sys.stdout.fileno(), select.POLLERR | select.POLLHUP)
    shown = read(cmd) or ""
    emit(shown)
    while True:
        wait(interval, watch)
        new = read(cmd)
        if new is None or new == shown:
            continue
        t0, last = time.monotonic(), shown
        while (t := (time.monotonic() - t0) * 1000 / ANIM_MS) < 1:
            f = frame(shown, new, ease(len(shown), len(new), t))
            if f != last:
                last = f
                emit(f)
            wait(FRAME_MS / 1000, watch)
        if last != new:
            emit(new)
        shown = new


if __name__ == "__main__":
    sys.exit(main())
