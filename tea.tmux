#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux_option_or_fallback() {
	local option_value
	option_value="$(tmux show-option -gqv "$1")"
	if [ -z "$option_value" ]; then
		option_value="$2"
	fi
	echo "$option_value"
}

tmux bind-key "$(tmux_option_or_fallback "@tea-bind" "t")" run-shell "$CURRENT_DIR/bin/tea.sh"

# Open tea on control + t
tmux bind-key -n C-t run-shell "$CURRENT_DIR/bin/tea.sh"

