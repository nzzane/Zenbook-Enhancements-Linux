#!/bin/bash
# gnome-keybinding.sh ID NAME BINDING COMMAND
#
# Add or update a GNOME custom keyboard shortcut without touching the others.
#   ./gnome-keybinding.sh camtoggle 'Toggle webcam' XF86WebCam '/usr/local/bin/camtoggle toggle'

set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 ID NAME BINDING COMMAND" >&2
    exit 2
fi

ID=$1 NAME=$2 BINDING=$3 COMMAND=$4
SCHEMA=org.gnome.settings-daemon.plugins.media-keys
DIR=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$ID/

LIST=$(gsettings get "$SCHEMA" custom-keybindings)
if [[ "$LIST" != *"'$DIR'"* ]]; then
    if [[ "$LIST" == "@as []" || "$LIST" == "[]" ]]; then
        LIST="['$DIR']"
    else
        LIST="${LIST%]}, '$DIR']"
    fi
    gsettings set "$SCHEMA" custom-keybindings "$LIST"
fi

KEY="$SCHEMA.custom-keybinding:$DIR"
gsettings set "$KEY" name "$NAME"
gsettings set "$KEY" command "$COMMAND"
gsettings set "$KEY" binding "$BINDING"
echo "$NAME: $BINDING -> $COMMAND"
