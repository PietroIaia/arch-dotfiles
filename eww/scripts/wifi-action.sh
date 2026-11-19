#!/bin/bash
# Usage: wifi-action.sh connect|prompt|password <ssid-hex> | disconnect | cancel
# Hex keeps any SSID inert in the onclick shell. password reads the psk from stdin; eww also substitutes
# {0} inside it (a psk containing "{0}" arrives mangled) and logs the command under --debug or on timeout.
source ~/.config/eww/scripts/lib/pending-action.sh
# detach_onclick nulls stdin; fd 3 carries the psk to the worker.
[ "${1:-}" = password ] && exec 3<&0
detach_onclick "$@"
shift

LIST="$HOME/.config/eww/scripts/wifi-networks.sh"

# popup_reopen <focus>; toggle-popup.sh's lock keeps a concurrent toggle from interleaving.
popup_reopen() {
    exec 8>"${XDG_RUNTIME_DIR:-/tmp}/eww-popup-toggle.lock"
    flock 8
    [ "$(eww get popup_open)" = network-window ] &&
        eww open network-window --screen "$(eww get popup_screen)" --arg focus="$1" --arg animate=false
    exec 8>&-
}

# prompt_show <hex|""> <error> <focus>: rebuild the list around the field, then reopen to move the keyboard.
prompt_show() {
    eww update wifi_prompt="$1" wifi_prompt_error="$2"
    [ "$(eww get popup_open)" = network-window ] || return 0
    eww update wifi_networks="$("$LIST" 9>&-)"
    popup_reopen "$3"
}

# The field may have been cancelled, or replaced after a reopen, while an attempt ran.
prompt_is_mine() { [ "$(eww get wifi_prompt)" = "$HEX" ]; }

pending_after() {
    # A close/reopen during the refresh resets the prompt; grabbing the keyboard then would leave no field.
    if [ "${REOPEN:-}" = true ] && ! prompt_is_mine; then return; fi
    if [ -n "${REOPEN:-}" ]; then popup_reopen "$REOPEN"; fi
}

# Prints the UUIDs of saved profiles for <ssid-hex>.
saved_uuids() {
    local uuids
    mapfile -t uuids < <(nmcli -t -f UUID,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }')
    (( ${#uuids[@]} )) || return 0
    nmcli -t -f connection.uuid,802-11-wireless.ssid connection show "${uuids[@]}" \
        | LC_ALL=C gawk -i ~/.config/eww/scripts/lib/wifi.awk -v want="$1" '
            sub(/^connection\.uuid:/, "") { uuid = $0 }
            sub(/^802-11-wireless\.ssid:/, "") && hex(unescape($0)) == want { print uuid }'
}

active_wifi() {
    nmcli -t -f UUID,TYPE connection show --active | awk -F: '$2 == "802-11-wireless" { print $1; exit }'
}

# One radio: NM drops the current network to try another, so a failed attempt brings it back.
# Detached and without the lock fd, so a retry isn't blocked while it reconnects.
restore_wifi() {
    if [ -n "$1" ]; then setsid timeout 30 nmcli connection up uuid "$1" </dev/null >/dev/null 2>&1 9>&- & fi
}

connect_error() {
    case "$2" in
        *"Secrets were required"*) echo "Wrong password" ;;
        *"psk: property is invalid"*) echo "Password must be 8–63 characters" ;;
        *"property is invalid"*) echo "Invalid password" ;;
        *) if [ "$1" = 124 ]; then echo "Timed out, try again"; else echo "Couldn't connect"; fi ;;
    esac
}

ACTION="${1:-}"
case "$ACTION" in
    connect|prompt|password)
        HEX="${2:-}"
        [[ $HEX =~ ^([0-9a-f]{2})+$ ]] || exit 1
        SSID=$(printf '%b' "$(sed 's/../\\x&/g' <<<"$HEX")")
        ;;
    disconnect|cancel)
        ;;
    *)
        exit 1
        ;;
esac

case "$ACTION" in
    prompt)
        prompt_show "$HEX" "" true
        ;;
    cancel)
        prompt_show "" "" false
        ;;
    connect)
        pending_begin wifi_pending "$HEX" network-window wifi_networks="$LIST"
        prev=$(active_wifi)
        out=$(timeout 30 nmcli device wifi connect "$SSID" 2>&1) && exit 0
        restore_wifi "$prev"
        # A saved profile whose secrets were rejected: the refresh on exit inserts the field.
        # Only key-mgmt nmcli can set a password for (none is WEP); 802.1X stays as before.
        uuid=$(saved_uuids "$HEX" | head -n 1)
        keymgmt=$(nmcli -g 802-11-wireless-security.key-mgmt connection show "$uuid" 2>/dev/null)
        if [[ $out == *"Secrets were required"* && $keymgmt =~ ^(none|wpa-psk|sae)$ ]]; then
            eww update wifi_prompt="$HEX" wifi_prompt_error="Wrong password"
            REOPEN=true
        fi
        ;;
    password)
        IFS= read -r PSK <&3
        exec 3<&-
        if [ -z "$PSK" ]; then
            eww update wifi_prompt_error="Enter a password"
            exit 0
        fi
        before=$(saved_uuids "$HEX")
        # No list refresh: a rebuild would drop the typed text and the keyboard focus.
        pending_begin wifi_pending "$HEX" network-window
        prompt_is_mine && eww update wifi_prompt_error=
        prev=$(active_wifi)
        if out=$(timeout 30 nmcli device wifi connect "$SSID" password "$PSK" 2>&1); then
            prompt_is_mine && prompt_show "" "" false
        else
            rc=$?
            # nmcli saves the new profile even when activation fails; a retry would reuse its bad psk.
            if [ -z "$before" ]; then
                mapfile -t created < <(saved_uuids "$HEX")
                (( ${#created[@]} )) && nmcli connection delete "${created[@]}" >/dev/null
            fi
            restore_wifi "$prev"
            prompt_is_mine && eww update wifi_prompt_error="$(connect_error "$rc" "$out")"
        fi
        ;;
    disconnect)
        pending_begin wifi_pending current network-window wifi_networks="$LIST"
        iface=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2 == "wifi" { print $1; exit }')
        [ -n "$iface" ] && timeout 10 nmcli device disconnect "$iface"
        ;;
esac
