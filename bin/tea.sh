#!/usr/bin/env bash

readonly DEFAULT_FIND_PATH="$HOME/Projects"
readonly DEFAULT_SHOW_NTH="-2,-1"
readonly DEFAULT_MAX_DEPTH="2"
readonly DEFAULT_PREVIEW_POSITION="top"
readonly DEFAULT_LAYOUT="reverse"
readonly DEFAULT_SESSION_NAME_STYLE="basename"
readonly DEFAULT_FZF_TMUX_OPTIONS="-p 90%"
readonly DEFAULT_EZA_OPTIONS="-ahlT -L=2 -s=extension --group-directories-first --icons --git --git-ignore --no-user --color=always --color-scale=all --color-scale-mode=gradient"
readonly DEFAULT_INCLUDE_SESSIONS="true"

readonly PROMPT='  '
readonly MARKER=''
readonly BORDER_LABEL='   tmux-tea   '
readonly HEADER='^f   ^j   ^s   ^w   ^p   ^a   ^x   '

# home path fix for sed
home_replacer=""
fzf_tmux_options=${FZF_TMUX_OPTS:-"$DEFAULT_FZF_TMUX_OPTIONS"}
[[ "$HOME" =~ ^[a-zA-Z0-9_/.@-]+$ ]] && home_replacer="s|^$HOME/|~/|"

# Cache tmux options for performance
TMUX_OPTIONS=$(tmux show-options -g | grep "^@tea-")

get_tmux_option() {
    local option="$1"
    local default="$2"
    local value

    if [[ -n "$TMUX_OPTIONS" ]]; then
        value=$(echo "$TMUX_OPTIONS" | grep "^$option " | cut -d' ' -f2- | tr -d '"')
    fi

    echo "${value:-$default}"
}

find_path=$(get_tmux_option "@tea-find-path" "$DEFAULT_FIND_PATH")
if [[ ! -d "$find_path" ]]; then
    find_path="~"
fi

show_nth=$(get_tmux_option "@tea-show-nth" "$DEFAULT_SHOW_NTH")
max_depth=$(get_tmux_option "@tea-max-depth" "$DEFAULT_MAX_DEPTH")
preview_position=$(get_tmux_option "@tea-preview-position" "$DEFAULT_PREVIEW_POSITION")
layout=$(get_tmux_option "@tea-layout" "$DEFAULT_LAYOUT")
session_name_style=$(get_tmux_option "@tea-session-name" "$DEFAULT_SESSION_NAME_STYLE")
default_command=$(get_tmux_option "@tea-default-command" "")
eza_options=$(get_tmux_option "@tea-eza-options" "$DEFAULT_EZA_OPTIONS")
include_sessions=$(get_tmux_option "@tea-include-sessions" "$DEFAULT_INCLUDE_SESSIONS")

session_preview_cmd="tmux capture-pane -ep -t \$(echo {} | awk '{print \$1}')"
dir_preview_cmd="$(which eza) ${eza_options}"
preview="$session_preview_cmd 2&>/dev/null || eval $dir_preview_cmd {}"

agent_patterns="antigravity|agy|aider|claude|copilot|codex|goose|interpreter|cline|cursor|windsurf|devin|openhands|swe-agent|autogpt"

pane_reload_cmd="tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}' | while read -r t c p; do sp=\$(echo \$p | sed -e \"$home_replacer\" | awk -F'/' '{if(NF>=2) print \$(NF-1)\"/\"\$(NF); else print \$0}'); echo \"\$t - \$c (\$sp)\"; done"
agent_reload_cmd="${pane_reload_cmd} | grep -iE '$agent_patterns'"

t_bind="ctrl-t:abort"
tab_bind="tab:down,btab:up"
session_bind="ctrl-s:change-prompt(  )+reload(tmux list-sessions -F '#S')+change-preview-window($preview_position,85%)"
zoxide_bind="ctrl-j:change-prompt(  )+reload(zoxide query -l | sed -e \"$home_replacer\")+change-preview(eval $dir_preview_cmd {})+change-preview-window(right)"
find_bind="ctrl-f:change-prompt(  )+reload(fd -H -d $max_depth -t d . $find_path | sed 's|/$||')+change-preview($dir_preview_cmd {})+change-preview-window(right)"
window_bind="ctrl-w:change-prompt(  )+reload(tmux list-windows -a -F '#{session_name}:#{window_index}')+change-preview($session_preview_cmd)+change-preview-window($preview_position)"
pane_bind="ctrl-p:change-prompt(  )+reload($pane_reload_cmd)+change-preview($session_preview_cmd)+change-preview-window($preview_position)"
agent_bind="ctrl-a:change-prompt(  )+reload($agent_reload_cmd)+change-preview($session_preview_cmd)+change-preview-window($preview_position)"
kill_bind="ctrl-x:change-prompt(  )+execute-silent(tmux kill-session -t {})+reload-sync(tmux list-sessions -F '#S' && zoxide query -l | sed -e \"$home_replacer\")"

# determine if the tmux server is running
tmux_running=1
tmux list-sessions &>/dev/null && tmux_running=0

# determine the user's current position relative tmux:
run_type="serverless"
[[ "$tmux_running" -eq 0 ]] && run_type=$([[ "$TMUX" ]] && echo "attached" || echo "detached")

get_sessions_by_last_used() {
    local current_session
    current_session=$(tmux display-message -p '#S' 2>/dev/null)

    tmux list-sessions -F '#{session_last_attached} #{session_name}' 2>/dev/null |
        sort --numeric-sort --reverse |
        awk '{print $2}' |
        if [[ -n "$current_session" ]]; then
            grep -v "^${current_session}$"
        else
            cat
        fi
}

get_windows_results() {
    tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null
}

format_pane_targets() {
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}' 2>/dev/null |
        while read -r target cmd path; do
            local short_path
            short_path=$(echo "$path" | sed -e "$home_replacer" | awk -F'/' '{if(NF>=2) print $(NF-1)"/"$NF; else print $0}')
            echo "${target} - ${cmd} (${short_path})"
        done
}

get_panes_results() {
    format_pane_targets
}

get_agent_results() {
    format_pane_targets | grep -iE "$agent_patterns"
}

get_zoxide_results() {
    zoxide query -l | sed -e "$home_replacer"
}

get_find_results() {
    fd -H -d "$max_depth" -t d . "$find_path" 2>/dev/null | sed 's|/$||'
}

get_fzf_results() {
    if [[ "$tmux_running" -eq 0 ]]; then
        local sessions=""
        if [[ "$include_sessions" == "true" ]]; then
            sessions=$(get_sessions_by_last_used)
        fi
        if [[ -n "$sessions" ]]; then
            echo "$sessions"
        fi
    fi
    get_zoxide_results
}

create_and_attach_session() {
    local result="$1"
    local session_name

    # Handle pane target: session_name:window_index.pane_index - command (path)
    local pane_target_regex='^([^:]+):([0-9]+)\.([0-9]+)'
    if [[ "$result" =~ $pane_target_regex ]]; then
        local target_session="${BASH_REMATCH[1]}"
        local target_window="${BASH_REMATCH[2]}"
        local target_pane="${BASH_REMATCH[3]}"
        tmux switch-client -t "${target_session}:${target_window}.${target_pane}" 2>/dev/null || tmux select-pane -t "${target_session}:${target_window}.${target_pane}" 2>/dev/null
        exit 0
    fi

    # Handle window target: session_name:window_index
    local window_target_regex='^([^:]+):([0-9]+)'
    if [[ "$result" =~ $window_target_regex ]]; then
        local target_session="${BASH_REMATCH[1]}"
        local target_window="${BASH_REMATCH[2]}"
        tmux switch-client -t "${target_session}:${target_window}" 2>/dev/null || tmux select-window -t "${target_session}:${target_window}" 2>/dev/null
        exit 0
    fi

    zoxide add "$result" &>/dev/null

    if [[ $result != /* ]]; then # not a dir path
        session_name=$result
    else
        if [[ "$session_name_style" = "full-path" ]]; then
            session_name="${result/$HOME/\~}"
        else
            session_name=$(basename "$result")
        fi
        session_name=$(echo "$session_name" | tr ' .:' '_')
    fi

    if [[ "$run_type" = "serverless" ]] || ! tmux has-session -t="$session_name" &>/dev/null; then
        if [[ -e "$result"/.tmuxinator.yml ]] && command -v tmuxinator &>/dev/null; then
            cd "$result" && tmuxinator local
        elif [[ -e "$HOME/.config/tmuxinator/$session_name.yml" ]] && command -v tmuxinator &>/dev/null; then
            tmuxinator "$session_name"
        else
            if [[ -n "$default_command" ]]; then
                tmux new-session -d -s "$session_name" -c "$result" "$default_command"
            else
                tmux new-session -d -s "$session_name" -c "$result"
            fi
        fi
    fi

    case $run_type in
    attached) tmux switch-client -t "$session_name" ;;
    detached | serverless) tmux attach -t "$session_name" ;;
    esac
}

show_help() {
    cat <<'EOF'
tmux-tea - tmux sessions as easy as tea

USAGE:
    tea [OPTIONS] [DIRECTORY...]

OPTIONS:
    -h, --help     Show this help message
    -s, --session  Start directly in session picker mode
    -w, --window   Start directly in window picker mode
    -p, --pane     Start directly in pane picker mode
    -a, --agent    Start directly in AI agent mode
    -z, --zoxide   Start directly in zoxide mode
    -f, --find     Start directly in find mode

ARGUMENTS:
    DIRECTORY      One or more directories to open as tmux sessions
                   Can be absolute paths or zoxide queries

EXAMPLES:
    tea            # Interactive mode with fzf
    tea -a         # Start directly in AI agent mode
    tea -s         # Start directly in session picker mode
    tea -w         # Start directly in window picker mode
    tea -p         # Start directly in pane picker mode
    tea -z         # Start directly in zoxide recent directories mode
    tea -f         # Start directly in find mode
    tea ~/myapp    # Open session for ~/Projects/myapp
    tea dir1 dir2  # Open multiple sessions using zoxide

KEYBINDINGS (Interactive mode):
    Ctrl+f         Directory mode (find directories)
    Ctrl+j         Zoxide mode (recent directories)
    Ctrl+s         Session mode (existing sessions)
    Ctrl+w         Window mode (existing windows)
    Ctrl+p         Pane mode (existing panes)
    Ctrl+a         Agent mode (running AI agents)
    Ctrl+x         Kill mode (delete sessions)
    Ctrl+t         Toggle tea

For more information, see: https://github.com/2kabhishek/tmux-tea
EOF
}

validate_directory_arg() {
    local arg="$1"

    if [[ -d "$arg" ]]; then
        echo "$arg"
        return 0
    elif zoxide query "$arg" &>/dev/null; then
        zoxide query "$arg"
        return 0
    else
        echo "No directory found for: $arg" >&2
        return 1
    fi
}

process_single_session() {
    local result="$1"

    if [[ -n "$home_replacer" ]]; then
        result="${result/#\~\//$HOME/}"
    fi
    create_and_attach_session "$result"
}

process_argument() {
    local arg="$1"
    local result

    if result=$(validate_directory_arg "$arg"); then
        process_single_session "$result"
        return 0
    else
        return 1
    fi
}

initial_mode="default"

if [[ $# -ge 1 ]]; then
    case "$1" in
    -h | --help)
        show_help
        exit 0
        ;;
    -s | --session)
        initial_mode="session"
        shift
        ;;
    -w | --window)
        initial_mode="window"
        shift
        ;;
    -p | --pane)
        initial_mode="pane"
        shift
        ;;
    -a | --agent)
        initial_mode="agent"
        shift
        ;;
    -z | --zoxide)
        initial_mode="zoxide"
        shift
        ;;
    -f | --find)
        initial_mode="find"
        shift
        ;;
    esac
fi

if [[ $# -ge 1 ]]; then
    if [[ $# -eq 1 ]]; then
        process_argument "$1" || exit 1
    else
        successful_sessions=0
        for arg in "$@"; do
            if process_argument "$arg"; then
                ((successful_sessions++))
            fi
        done

        if [[ $successful_sessions -eq 0 ]]; then
            echo "No valid directories found for any arguments." >&2
            exit 1
        fi
    fi
    exit 0
else
    nth_opts=""
    if [[ "$initial_mode" == "default" || "$initial_mode" == "zoxide" || "$initial_mode" == "find" ]]; then
        nth_opts="--delimiter=/ --with-nth=$show_nth --keep-right"
    fi

    if [[ "$initial_mode" == "session" ]]; then
        init_prompt='  '
        init_results=$(get_sessions_by_last_used)
        init_preview="$session_preview_cmd"
    elif [[ "$initial_mode" == "window" ]]; then
        init_prompt='  '
        init_results=$(get_windows_results)
        init_preview="$session_preview_cmd"
    elif [[ "$initial_mode" == "pane" ]]; then
        init_prompt='  '
        init_results=$(get_panes_results)
        init_preview="$session_preview_cmd"
    elif [[ "$initial_mode" == "agent" ]]; then
        init_prompt='🤖  '
        init_results=$(get_agent_results)
        init_preview="$session_preview_cmd"
    elif [[ "$initial_mode" == "zoxide" ]]; then
        init_prompt='  '
        init_results=$(get_zoxide_results)
        init_preview="eval $dir_preview_cmd {}"
    elif [[ "$initial_mode" == "find" ]]; then
        init_prompt='  '
        init_results=$(get_find_results)
        init_preview="$dir_preview_cmd {}"
    else
        init_prompt="$PROMPT"
        init_results=$(get_fzf_results)
        init_preview="$preview"
    fi

    case $run_type in
    attached)
        result=$(echo "$init_results" | fzf-tmux \
            --bind "$find_bind" --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$pane_bind" --bind "$agent_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$BORDER_LABEL" --header "$HEADER" \
            --no-sort --cycle $nth_opts --prompt "$init_prompt" --marker "$MARKER" \
            --preview "$init_preview" --preview-window="$preview_position",75% "$fzf_tmux_options" --layout="$layout")
        ;;
    detached)
        result=$(echo "$init_results" | fzf \
            --bind "$find_bind" --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$pane_bind" --bind "$agent_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$BORDER_LABEL" --header "$HEADER" \
            --no-sort --cycle $nth_opts --prompt "$init_prompt" --marker "$MARKER" \
            --preview "$init_preview" --preview-window=top,75%)
        ;;
    serverless)
        result=$(echo "$init_results" | fzf \
            --bind "$find_bind" --bind "$tab_bind" --bind "$zoxide_bind" --bind "$kill_bind" --bind "$t_bind" \
            --border-label "$BORDER_LABEL" --header "$HEADER" --no-sort --cycle $nth_opts \
            --prompt "$init_prompt" --marker "$MARKER" --preview "$dir_preview_cmd {}")
        ;;
    esac
fi

[[ -n "$result" ]] || exit 0

if [[ -n "$home_replacer" ]]; then
    result="${result/#\~\//$HOME/}"
fi

create_and_attach_session "$result"
