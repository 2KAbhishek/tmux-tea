#!/usr/bin/env bash

readonly DEFAULT_FIND_PATH="$HOME/Projects"
readonly DEFAULT_SHOW_NTH="-2,-1"
readonly DEFAULT_MAX_DEPTH="2"
readonly DEFAULT_PREVIEW_POSITION="top"
readonly DEFAULT_LAYOUT="reverse"
readonly DEFAULT_SESSION_NAME_STYLE="basename"
readonly DEFAULT_FZF_TMUX_OPTIONS="-p 90%"

readonly PROMPT='  '
readonly MARKER=''
readonly BORDER_LABEL='   tmux-tea   '
readonly HEADER='^f   ^j   ^s   ^w   ^x '

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

session_preview_cmd="tmux capture-pane -ep -t"
dir_preview_cmd="eza -ahlT -L=2 -s=extension --group-directories-first --icons --git --git-ignore --no-user --color=always --color-scale=all --color-scale-mode=gradient"
preview="$session_preview_cmd {} 2&>/dev/null || eval $dir_preview_cmd {}"

t_bind="ctrl-t:abort"
tab_bind="tab:down,btab:up"
session_bind="ctrl-s:change-prompt(  )+reload(tmux list-sessions -F '#S')+change-preview-window($preview_position,85%)"
zoxide_bind="ctrl-j:change-prompt(  )+reload(zoxide query -l | sed -e \"$home_replacer\")+change-preview(eval $dir_preview_cmd {})+change-preview-window(right)"
find_bind="ctrl-f:change-prompt(  )+reload(fd -H -d $max_depth -t d . $find_path | sed 's|/$||')+change-preview($dir_preview_cmd {})+change-preview-window(right)"
window_bind="ctrl-w:change-prompt(  )+reload(tmux list-windows -a -F '#{session_name}:#{window_index}')+change-preview($session_preview_cmd {})+change-preview-window($preview_position)"
kill_bind="ctrl-x:change-prompt(  )+execute-silent(tmux kill-session -t {})+reload-sync(tmux list-sessions -F '#S' && zoxide query -l | sed -e \"$home_replacer\")"

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
        { [[ -n "$current_session" ]] && grep -v "^${current_session}$" || cat; }
}

get_zoxide_results() {
    zoxide query -l | sed -e "$home_replacer"
}

get_fzf_results() {
    if [[ "$tmux_running" -eq 0 ]]; then
        sessions=$(get_sessions_by_last_used)
        [[ "$sessions" ]] && echo "$sessions" && get_zoxide_results || get_zoxide_results
    else
        get_zoxide_results
    fi
}

create_and_attach_session() {
    local result="$1"
    local session_name

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
    -h, --help      Show this help message

ARGUMENTS:
    DIRECTORY       One or more directories to open as tmux sessions
                    Can be absolute paths or zoxide queries

EXAMPLES:
    tea                          # Interactive mode with fzf
    tea ~/Projects/myapp         # Open session for ~/Projects/myapp
    tea work personal            # Open multiple sessions using zoxide
    tea ~/code/app1 ~/code/app2  # Open multiple sessions with paths

KEYBINDINGS (Interactive mode):
    Ctrl+f    Directory mode (find directories)
    Ctrl+j    Zoxide mode (recent directories)
    Ctrl+s    Session mode (existing sessions)
    Ctrl+w    Window mode (existing windows)
    Ctrl+x    Kill mode (delete sessions)
    Ctrl+t    Toggle tea / exit

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

    [[ $home_replacer ]] && result=$(echo "$result" | sed -e "s|^~/|$HOME/|")
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

if [[ $# -ge 1 ]]; then
    case "$1" in
    -h | --help)
        show_help
        exit 0
        ;;
    esac

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
    case $run_type in
    attached)
        result=$(get_fzf_results | fzf-tmux \
            --bind "$find_bind" --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$BORDER_LABEL" --header "$HEADER" \
            --no-sort --cycle --delimiter='/' --with-nth="$show_nth" --keep-right --prompt "$PROMPT" --marker "$MARKER" \
            --preview "$preview" --preview-window="$preview_position",75% "$fzf_tmux_options" --layout="$layout")
        ;;
    detached)
        result=$(get_fzf_results | fzf \
            --bind "$find_bind" --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$BORDER_LABEL" --header "$HEADER" \
            --no-sort --cycle --delimiter='/' --with-nth="$show_nth" --keep-right --prompt "$PROMPT" --marker "$MARKER" \
            --preview "$preview" --preview-window=top,75%)
        ;;
    serverless)
        result=$(get_fzf_results | fzf \
            --bind "$find_bind" --bind "$tab_bind" --bind "$zoxide_bind" --bind "$kill_bind" --bind "$t_bind" \
            --border-label "$BORDER_LABEL" --header "$HEADER" --no-sort --cycle --delimiter='/' --with-nth="$show_nth" \
            --keep-right --prompt "$PROMPT" --marker "$MARKER" --preview "$dir_preview_cmd {}")
        ;;
    esac
fi

[[ "$result" ]] || exit 0

[[ $home_replacer ]] && result=$(echo "$result" | sed -e "s|^~/|$HOME/|")

create_and_attach_session "$result"
