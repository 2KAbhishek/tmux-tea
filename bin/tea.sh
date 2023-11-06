#!/usr/bin/env bash

# home path fix for sed
HOME_REPLACER=""
echo "$HOME" | grep -E "^[a-zA-Z0-9\-_/.@]+$" &>/dev/null
HOME_SED_SAFE=$?
if [ $HOME_SED_SAFE -eq 0 ]; then
	HOME_REPLACER="s|^$HOME/|~/|"
fi

BORDER_LABEL='   tmux-tea   '
HEADER=" ^s sessions ^x zoxide ^f find"
SESSION_BIND="ctrl-s:change-prompt(  )+reload(tmux list-sessions -F '#S')"
ZOXIDE_BIND="ctrl-x:change-prompt(  )+reload(zoxide query -l | sed -e \"$HOME_REPLACER\")"
FIND_BIND="ctrl-f:change-prompt(  )+reload(fd -H -d 2 -t d . ~)"
TAB_BIND="tab:down,btab:up"
PROMPT='  '
MARKER=''
PREVIEW="tmux list-panes -t {} -aF '#S-  #I:#W:#P   #T #{window_active}:#{pane_active}' | grep {}- | cut -d ' ' -f 2-"

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

if [ $# -eq 1 ]; then
	zoxide query "$1" &>/dev/null
	ZOXIDE_RESULT_EXIT_CODE=$?
	if [ $ZOXIDE_RESULT_EXIT_CODE -eq 0 ]; then
		RESULT=$(zoxide query "$1")
	else
		ls "$1" &>/dev/null
		LS_EXIT_CODE=$?
		if [ $LS_EXIT_CODE -eq 0 ]; then
			RESULT=$1
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
				--bind "$FIND_BIND" --bind "$SESSION_BIND" --bind "$TAB_BIND" \
				--bind "$ZOXIDE_BIND" --border-label "$BORDER_LABEL" --header "$HEADER" \
				--no-sort --prompt "$PROMPT" --marker "$MARKER" --preview "$PREVIEW" \
				"$FZF_TMUX_OPTS"
		)
		;;
	detached)
		RESULT=$(
			(get_fzf_results) | fzf \
				--bind "$FIND_BIND" --bind "$SESSION_BIND" --bind "$TAB_BIND" \
				--bind "$ZOXIDE_BIND" --border-label "$BORDER_LABEL" --header "$HEADER" \
				--no-sort --prompt "$PROMPT" --marker "$MARKER" --preview "$PREVIEW"
		)
		;;
	serverless)
		RESULT=$(
			(get_fzf_results) | fzf \
				--bind "$FIND_BIND" --bind "$TAB_BIND" --bind "$ZOXIDE_BIND" \
				--border-label "$BORDER_LABEL" --header "$HEADER" --no-sort \
				--prompt "$PROMPT" --marker "$MARKER" --preview "$PREVIEW"
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
	SESSION_NAME=$(basename "$RESULT" | tr ' .:' '_')
fi

if [ "$T_RUNTYPE" != "serverless" ]; then
	SESSION=$(tmux list-sessions -F '#S' | grep "^$SESSION_NAME$")
fi

if [ "$SESSION" = "" ]; then
	SESSION="$SESSION_NAME"
	if [ -e "$RESULT"/.tmuxinator.yml ]; then
		cd "$RESULT" && tmuxinator local
	elif [ -e "$HOME/.config/tmuxinator/$SESSION.yml" ]; then
		tmuxinator "$SESSION"
	else
		tmux new-session -d -s "$SESSION" -c "$RESULT"
	fi
fi

case $T_RUNTYPE in
attached)
	tmux switch-client -t "$SESSION"
	;;
detached) ;&
serverless)
	tmux attach -t "$SESSION"
	;;
esac
