#!/bin/bash
# Shows every palette-styled pop-up one after another (plan.md T4-T8, plus a GTK3 dialog).
# eww pop-ups advance on their own; close each dialog (any button / Cancel) to advance.
set -u
POP="$HOME/.config/eww/scripts/toggle-popup.sh"
SCREEN="${1:-0}"   # eww screen index for the bar pop-ups (0 = HDMI)
step() { printf '\n▶ %s\n' "$*"; }

step "eww bar pop-ups (3s each)"
for p in calendar-window network-window volume-window power-window; do
    echo "  $p"
    "$POP" --worker "$p" "$SCREEN"; sleep 3
    "$POP" --worker "$p" "$SCREEN"; sleep 0.3
done

step "Notification (eww notification daemon)"
notify-send "Palette" "Notification check"; sleep 4

step "GTK4 / libadwaita dialog (zenity)"
zenity --question --title "Palette" --text "GTK4 dialog check" 2>/dev/null

step "GTK3 message dialog"
/usr/bin/python3 -I -c '
import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk
d = Gtk.MessageDialog(message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.YES_NO, text="Palette")
d.format_secondary_text("GTK3 dialog check"); d.set_title("gtk3-check"); d.run()'

step "GTK3 file chooser"
/usr/bin/python3 -I -c '
import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk
d = Gtk.FileChooserDialog(title="GTK3 file chooser check", action=Gtk.FileChooserAction.OPEN)
d.add_buttons("_Cancel", Gtk.ResponseType.CANCEL, "_Open", Gtk.ResponseType.ACCEPT); d.run()'

step "GTK4 file chooser (zenity)"
zenity --file-selection --title "GTK4 file chooser check" >/dev/null 2>&1

step "Polkit prompt (runs 'true' — entering the password or cancelling are both harmless)"
pkexec true

step "Done"
