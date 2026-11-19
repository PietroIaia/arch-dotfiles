# Shared by bluetooth-devices.sh and bluetooth-connected.sh (loaded with jq -L).

# BlueZ Device1.Icon name to Nerd Font glyph.
def icon:
  {
    "audio-headphones": "󰋋", "audio-headset": "󰋎", "audio-card": "󰓃",
    "input-keyboard": "󰌌", "input-mouse": "󰍽", "input-gaming": "󰊴",
    "input-tablet": "󰓶", "phone": "󰏲", "computer": "󰟀",
    "video-display": "󰍹", "multimedia-player": "󰎈",
    "camera-photo": "󰄀", "camera-video": "󰄀", "printer": "󰐪"
  }[. // ""] // "󰂯";

# Device1 objects from `busctl --json=short … GetManagedObjects` output.
def devices:
  [ (.data[0] // {}) | to_entries[]
    | .value["org.bluez.Device1"] // empty
    | { mac: .Address.data,
        name: (.Alias.data // .Name.data // .Address.data),
        icon: .Icon.data,
        connected: (.Connected.data // false),
        rssi: .RSSI.data } ];
