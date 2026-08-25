#!/usr/bin/env bash

CURRENT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

tmux_option_or_fallback() {
    local option_value
    option_value="$(tmux show-option -gqv "$1")"
    option_value="${option_value#\"}"
    option_value="${option_value%\"}"
    option_value="${option_value#\'}"
    option_value="${option_value%\'}"
    if [ -z "$option_value" ]; then
        option_value="$2"
    fi
    printf '%s\n' "$option_value"
}

KEY_BIND="$(tmux_option_or_fallback "@tea-bind" "t")"
if [ "$KEY_BIND" != "false" ]; then
    tmux bind-key "$KEY_BIND" run-shell "\"$CURRENT_DIR/bin/tea.sh\""
fi

ALT_KEY_BIND="$(tmux_option_or_fallback "@tea-alt-bind" "C-t")"
if [ "$ALT_KEY_BIND" != "false" ]; then
    tmux bind-key -n "$ALT_KEY_BIND" run-shell "\"$CURRENT_DIR/bin/tea.sh\""
fi
