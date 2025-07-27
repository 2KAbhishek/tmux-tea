#!/usr/bin/env bash

# home path fix for sed
home_replacer=""
fzf_tmux_options=${FZF_TMUX_OPTS:-"-p 90%"}
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

find_path=$(get_tmux_option "@tea-find-path" "$HOME/Projects")
if [[ ! -d "$find_path" ]]; then
    find_path="~"
fi

show_nth=$(get_tmux_option "@tea-show-nth" "-2,-1")
max_depth=$(get_tmux_option "@tea-max-depth" "2")
preview_position=$(get_tmux_option "@tea-preview-position" "top")
layout=$(get_tmux_option "@tea-layout" "reverse")
session_name_style=$(get_tmux_option "@tea-session-name" "basename")
default_command=$(get_tmux_option "@tea-default-command" "")

session_preview_cmd="tmux capture-pane -ep -t"
dir_preview_cmd="eza -ahlT -L=2 -s=extension --group-directories-first --icons --git --git-ignore --no-user --color=always --color-scale=all --color-scale-mode=gradient"
preview="$session_preview_cmd {} 2&>/dev/null || eval $dir_preview_cmd {}"

prompt='  '
marker=''
border_label='   tmux-tea   '
header="^f   ^j   ^s   ^w   ^x "

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
    tmux list-sessions -F '#{session_last_attached} #{session_name}' |
        sort --numeric-sort --reverse | awk '{print $2}' | grep -v -E "^$(tmux display-message -p '#S')$"
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

# if started with arguments
if [[ $# -ge 1 ]]; then
    process_argument() {
        local arg="$1"
        local result

        if [[ -d "$arg" ]]; then
            result="$arg"
        else
            if zoxide query "$arg" &>/dev/null; then
                result=$(zoxide query "$arg")
            else
                echo "No directory found for: $arg" >&2
                return 1
            fi
        fi

        [[ $home_replacer ]] && result=$(echo "$result" | sed -e "s|^~/|$HOME/|")
        create_and_attach_session "$result"
        return 0
    }

    if [[ $# -eq 1 ]]; then
        process_argument "$1" || exit 1
    else
        # Multiple arguments - process each one
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
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$border_label" --header "$header" \
            --no-sort --cycle --delimiter='/' --with-nth="$show_nth" --keep-right --prompt "$prompt" --marker "$marker" \
            --preview "$preview" --preview-window="$preview_position",75% "$fzf_tmux_options" --layout="$layout")
        ;;
    detached)
        result=$(get_fzf_results | fzf \
            --bind "$find_bind" --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$border_label" --header "$header" \
            --no-sort --cycle --delimiter='/' --with-nth="$show_nth" --keep-right --prompt "$prompt" --marker "$marker" \
            --preview "$preview" --preview-window=top,75%)
        ;;
    serverless)
        result=$(get_fzf_results | fzf \
            --bind "$find_bind" --bind "$tab_bind" --bind "$zoxide_bind" --bind "$kill_bind" --bind "$t_bind" \
            --border-label "$border_label" --header "$header" --no-sort --cycle --delimiter='/' --with-nth="$show_nth" \
            --keep-right --prompt "$prompt" --marker "$marker" --preview "$dir_preview_cmd {}")
        ;;
    esac
fi

[[ "$result" ]] || exit 0

[[ $home_replacer ]] && result=$(echo "$result" | sed -e "s|^~/|$HOME/|")

create_and_attach_session "$result"
