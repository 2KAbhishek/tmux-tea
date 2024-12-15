#!/usr/bin/env bash

# home path fix for sed
home_replacer=""
fzf_tmux_options=${FZF_TMUX_OPTS:-"-p 90%"}
[[ "$HOME" =~ ^[a-zA-Z0-9\-_/.@]+$ ]] && home_replacer="s|^$HOME/|~/|"

results_cycle_option=$(tmux show-option -gqv "@tea-results-cycle")
results_cycle="--cycle"
if [[ "$results_cycle_option" != "true" ]]; then
    results_cycle="--cycle"
fi

max_depth_option=$(tmux show-option -gqv "@tea-max-depth")
max_depth=${max_depth_option:-"2"}

preview_position_option=$(tmux show-option -gqv "@tea-preview-position")
preview_position=${preview_position_option:-"top"}

layout_option=$(tmux show-option -gqv "@tea-layout")
layout=${layout_option:-"reverse"}

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
find_bind="ctrl-f:change-prompt(  )+reload(fd -H -d $max_depth -t d . ~)+change-preview($dir_preview_cmd {})+change-preview-window(right)"
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

# if started with single argument
if [[ $# -eq 1 ]]; then
    if [[ -d "$1" ]]; then
        result=$1
    else
        zoxide query "$1" &>/dev/null
        zoxide_result_exit_code=$?
        if [[ $zoxide_result_exit_code -eq 0 ]]; then
            result=$(zoxide query "$1")
        else
            echo "No directory found."
            exit 1
        fi
    fi
else
    case $run_type in
    attached)
        result=$(get_fzf_results | fzf-tmux \
            --bind "$find_bind" --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$border_label" --header "$header" \
            --no-sort --prompt "$prompt" --marker "$marker" --preview "$preview" \
            --preview-window="$preview_position",75% "$fzf_tmux_options" --layout="$layout" $results_cycle)
        ;;
    detached)
        result=$(get_fzf_results | fzf \
            --bind "$find_bind" --bind "$session_bind" --bind "$tab_bind" --bind "$window_bind" --bind "$t_bind" \
            --bind "$zoxide_bind" --bind "$kill_bind" --border-label "$border_label" --header "$header" \
            --no-sort --prompt "$prompt" --marker "$marker" --preview "$preview" \
            --preview-window=top,75%)
        ;;
    serverless)
        result=$(get_fzf_results | fzf \
            --bind "$find_bind" --bind "$tab_bind" --bind "$zoxide_bind" --bind "$kill_bind" --bind "$t_bind" \
            --border-label "$border_label" --header "$header" --no-sort --prompt "$prompt" --marker "$marker" \
            --preview "$dir_preview_cmd {}")
        ;;
    esac
fi

[[ "$result" ]] || exit 0

[[ $home_replacer ]] && result=$(echo "$result" | sed -e "s|^~/|$HOME/|")

zoxide add "$result" &>/dev/null

if [[ $result != /* ]]; then # not a dir path
    session_name=$result
else
    session_name_option=$(tmux show-option -gqv "@tea-session-name")
    if [[ "$session_name_option" = "full-path" ]]; then
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
        default_cmd=$(tmux show-option -gqv "@tea-default-command")
        if [[ -n "$default_cmd" ]]; then
            tmux new-session -d -s "$session_name" -c "$result" "$default_cmd"
        else
            tmux new-session -d -s "$session_name" -c "$result"
        fi
    fi
fi

case $run_type in
attached) tmux switch-client -t "$session_name" ;;
detached | serverless) tmux attach -t "$session_name" ;;
esac
