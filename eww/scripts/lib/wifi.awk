# Sourced with gawk -i: SSID helpers shared by the wifi scripts.

BEGIN { for (i = 0; i < 256; i++) { ord[sprintf("%c", i)] = i } }

# Undoes nmcli terse escaping ("\:" and "\\").
function unescape(s,    out, i, c) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < length(s)) { i++; c = substr(s, i, 1) }
    out = out c
  }
  return out
}

# Hex is the only form of an SSID in shell and expressions: any byte stays inert there.
function hex(s,    out, i) {
  out = ""
  for (i = 1; i <= length(s); i++) { out = out sprintf("%02x", ord[substr(s, i, 1)]) }
  return out
}
