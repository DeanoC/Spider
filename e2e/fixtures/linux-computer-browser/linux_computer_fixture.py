#!/usr/bin/env python3

import json
import os
import signal
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402


STATE_PATH = Path(os.environ.get("SPIDER_FIXTURE_STATE_PATH", "/tmp/spider-linux-computer-fixture-state.json"))
WINDOW_TITLE = os.environ.get("SPIDER_FIXTURE_WINDOW_TITLE", "Spider Linux Computer Fixture")
BUTTON_TITLE = os.environ.get("SPIDER_FIXTURE_BUTTON_TITLE", "Press Linux Fixture Button")
INITIAL_TEXT = os.environ.get("SPIDER_FIXTURE_INITIAL_TEXT", "")
APP_NAME = os.environ.get("SPIDER_FIXTURE_APP_NAME", "SpiderLinuxComputerFixture")


class FixtureApp:
    def __init__(self) -> None:
        GLib.set_prgname(APP_NAME)
        GLib.set_application_name(APP_NAME)

        self.button_presses = 0
        self.window = Gtk.Window(title=WINDOW_TITLE)
        self.window.set_default_size(480, 220)
        self.window.connect("destroy", self.on_destroy)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.set_border_width(18)

        instructions = Gtk.Label(
            label="Spider Linux computer fixture: press the button, then type into the field."
        )
        instructions.set_xalign(0.0)
        instructions.set_line_wrap(True)
        root.pack_start(instructions, False, False, 0)

        self.entry = Gtk.Entry()
        self.entry.set_text(INITIAL_TEXT)
        self.entry.connect("changed", self.on_changed)
        root.pack_start(self.entry, False, False, 0)

        self.button = Gtk.Button(label=BUTTON_TITLE)
        self.button.connect("clicked", self.on_button_clicked)
        root.pack_start(self.button, False, False, 0)

        self.status = Gtk.Label(label="idle")
        self.status.set_xalign(0.0)
        root.pack_start(self.status, False, False, 0)

        self.window.add(root)
        self.window.show_all()
        self.write_state()

    def on_changed(self, _widget: Gtk.Widget) -> None:
        self.write_state()

    def on_button_clicked(self, _widget: Gtk.Widget) -> None:
        self.button_presses += 1
        self.status.set_text(f"clicked:{self.entry.get_text()}")
        self.write_state()

    def on_destroy(self, _widget: Gtk.Widget) -> None:
        self.write_state()
        Gtk.main_quit()

    def write_state(self) -> None:
        payload = {
            "app_name": APP_NAME,
            "window_title": WINDOW_TITLE,
            "button_title": BUTTON_TITLE,
            "text_value": self.entry.get_text(),
            "button_presses": self.button_presses,
            "status": self.status.get_text(),
        }
        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        STATE_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    app = FixtureApp()

    def handle_signal(signum, _frame) -> None:
        app.write_state()
        Gtk.main_quit()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
