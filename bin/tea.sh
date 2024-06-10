#!/usr/bin/env bash

# home path fix for sed
HOME_REPLACER=""
FZF_TMUX_OPTIONS=${FZF_TMUX_OPTS:-"-p 90%"}
echo "$HOME" | grep -E "^[a-zA-Z0-9\-_/.@]+$" &>/dev/null
HOME_SED_SAFE=$?
if [ $HOME_SED_SAFE -eq 0 ]; then
    HOME_REPLACER="s|^$HOME/|~/|"
fi

SESSION_PREVIEW_CMD="tmux capture-pane -ep -t"
DIR_PREVIEW_CMD="eza -ahlT -L=2 -s=extension --group-directories-first --icons --git --git-ignore --no-user --color=always --color-scale=all --color-scale-mode=gradient"
PREVIEW="$SESSION_PREVIEW_CMD {} 2&>/dev/null || eval $DIR_PREVIEW_CMD {}"

PROMPT='  '
MARKER=''
BORDER_LABEL='   tmux-tea   '
HEADER="^f   ^j   ^s   ^w   ^x "

T_BIND="ctrl-t:abort"
TAB_BIND="tab:down,btab:up"
SESSION_BIND="ctrl-s:change-prompt(  )+reload(tmux list-sessions -F '#S')+change-preview-window(top,85%)"
ZOXIDE_BIND="ctrl-j:change-prompt(  )+reload(zoxide query -l | sed -e \"$HOME_REPLACER\")+change-preview(eval $DIR_PREVIEW_CMD {})+change-preview-window(right)"
FIND_BIND="ctrl-f:change-prompt(  )+reload(fd -H -d 2 -t d . ~)+change-preview($DIR_PREVIEW_CMD {})+change-preview-window(right)"
WINDOW_BIND="ctrl-w:change-prompt(  )+reload(tmux list-windows -a -F '#{session_name}:#{window_index}')+change-preview($SESSION_PREVIEW_CMD {})+change-preview-window(top)"
KILL_BIND="ctrl-x:change-prompt(  )+execute-silent(tmux kill-session -t {})+reload-sync(tmux list-sessions -F '#S' && zoxide query -l | sed -e \"$HOME_REPLACER\")"

# determine if the tmux server is running
if tmux list-sessions &>/dev/null; then
    TMUX_RUNNING=0
else
    TMUX_RUNNING=1
fi

# determine the user's current position relative tmux:
T_RUNTYPE="serverless"
if [ "$TMUX_RUNNING" -eq 0 ]; then
    if [ "$TMUX" ]; then
        T_RUNTYPE="attached"
    else
        T_RUNTYPE="detached"
    fi
fi

get_sessions_by_last_used() {
    tmux list-sessions -F '#{session_last_attached} #{session_name}' |
        sort --numeric-sort --reverse | awk '{print $2}' | grep -v "$(tmux display-message -p '#S')"
}

get_zoxide_results() {
    zoxide query -l | sed -e "$HOME_REPLACER"
}

get_fzf_results() {
    if [ "$TMUX_RUNNING" -eq 0 ]; then
        SESSIONS=$(get_sessions_by_last_used)
        if [ "$SESSIONS" != "" ]; then
            echo "$SESSIONS" && get_zoxide_results
        else
            get_zoxide_results
        fi
    else
        get_zoxide_results
    fi
}

# if started with single argument
if [ $# -eq 1 ]; then
    if [ -d "$1" ]; then
        RESULT=$1
    else
        zoxide query "$1" &>/dev/null
        ZOXIDE_RESULT_EXIT_CODE=$?
        if [ $ZOXIDE_RESULT_EXIT_CODE -eq 0 ]; then
            RESULT=$(zoxide query "$1")
        else
            echo "No directory found."
            exit 1
        fi
    fi
else
    case $T_RUNTYPE in
    attached)
        RESULT=$(
            (get_fzf_results) | fzf-tmux \
                --bind "$FIND_BIND" --bind "$SESSION_BIND" --bind "$TAB_BIND" --bind "$WINDOW_BIND" --bind "$T_BIND" \
                --bind "$ZOXIDE_BIND" --bind "$KILL_BIND" --border-label "$BORDER_LABEL" --header "$HEADER" \
                --no-sort --prompt "$PROMPT" --marker "$MARKER" --preview "$PREVIEW" \
                --preview-window=top,75% $FZF_TMUX_OPTIONS
        )
        ;;
    detached)
        RESULT=$(
            (get_fzf_results) | fzf \
                --bind "$FIND_BIND" --bind "$SESSION_BIND" --bind "$TAB_BIND" --bind "$WINDOW_BIND" --bind "$T_BIND" \
                --bind "$ZOXIDE_BIND" --bind "$KILL_BIND" --border-label "$BORDER_LABEL" --header "$HEADER" \
                --no-sort --prompt "$PROMPT" --marker "$MARKER" --preview "$PREVIEW" \
                --preview-window=top,75%
        )
        ;;
    serverless)
        RESULT=$(
            (get_fzf_results) | fzf \
                --bind "$FIND_BIND" --bind "$TAB_BIND" --bind "$ZOXIDE_BIND" --bind "$KILL_BIND" --bind "$T_BIND" \
                --border-label "$BORDER_LABEL" --header "$HEADER" --no-sort --prompt "$PROMPT" --marker "$MARKER" \
                --preview "$DIR_PREVIEW_CMD {}"
        )
        ;;
    esac
fi

if [ "$RESULT" = "" ]; then
    exit 0
fi

if [ $HOME_SED_SAFE -eq 0 ]; then
    RESULT=$(echo "$RESULT" | sed -e "s|^~/|$HOME/|")
fi

zoxide add "$RESULT" &>/dev/null

if [[ $RESULT != /* ]]; then # not a dir path
    SESSION_NAME=$RESULT
else
    SESSION_NAME_OPTION=$(tmux show-option -gqv "@tea-session-name")
    if [ "$SESSION_NAME_OPTION" = "full-path" ]; then
        SESSION_NAME="${RESULT/$HOME/\~}"
    else
        SESSION_NAME=$(basename "$RESULT")
    fi
    SESSION_NAME=$(echo "$SESSION_NAME" | tr ' .:' '_')
fi

if [ "$T_RUNTYPE" = "serverless" ] || ! tmux has-session -t="$SESSION_NAME" &>/dev/null; then
    if [ -e "$RESULT"/.tmuxinator.yml ] && command -v tmuxinator &>/dev/null; then
        cd "$RESULT" && tmuxinator local
    elif [ -e "$HOME/.config/tmuxinator/$SESSION_NAME.yml" ] && command -v tmuxinator &>/dev/null; then
        tmuxinator "$SESSION_NAME"
    else
        tmux new-session -d -s "$SESSION_NAME" -c "$RESULT"
    fi
fi

case $T_RUNTYPE in
attached) tmux switch-client -t "$SESSION_NAME" ;;
detached | serverless) tmux attach -t "$SESSION_NAME" ;;
esac
