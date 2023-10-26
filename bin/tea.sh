#!/usr/bin/env bash

# determine if the tmux server is running
if tmux list-sessions &>/dev/null; then
	TMUX_RUNNING=0
else
	TMUX_RUNNING=1
fi

# determine the user's current position relative tmux:
T_RUNTYPE="serverless"
if [ "$TMUX_RUNNING" -eq 0 ]; then
	if [ "$TMUX" ]; then # inside tmux
		T_RUNTYPE="attached"
	else # outside tmux
		T_RUNTYPE="detached"
	fi
fi

HOME_REPLACER=""                                          # default to a noop
echo "$HOME" | grep -E "^[a-zA-Z0-9\-_/.@]+$" &>/dev/null # chars safe to use in sed
HOME_SED_SAFE=$?
if [ $HOME_SED_SAFE -eq 0 ]; then # $HOME should be safe to use in sed
	HOME_REPLACER="s|^$HOME/|~/|"
fi

get_sessions_by_mru() {
	tmux list-sessions -F '#{session_last_attached} #{session_name}' | sort --numeric-sort --reverse | awk '{print $2}'
}

get_zoxide_results() {
	zoxide query -l | sed -e "$HOME_REPLACER"
}

get_fzf_results() {
	if [ "$TMUX_RUNNING" -eq 0 ]; then
		fzf_default_results="$(tmux show -gqv '@t-fzf-default-results')"
		case $fzf_default_results in
		sessions)
			get_sessions_by_mru
			;;
		zoxide)
			get_zoxide_results
			;;
		*)
			get_sessions_by_mru && get_zoxide_results # default shows both
			;;
		esac
	else
		get_zoxide_results # only show zoxide results when outside tmux
	fi
}

BORDER_LABEL='   tmux-tea   '
HEADER=" ^s sessions ^x zoxide ^f find"
SESSION_BIND="ctrl-s:change-prompt(  )+reload(tmux list-sessions -F '#S')"
ZOXIDE_BIND="ctrl-x:change-prompt(  )+reload(zoxide query -l | sed -e \"$HOME_REPLACER\")"
FIND_BIND="ctrl-f:change-prompt(  )+reload(fd -H -d 2 -t d . ~)"
TAB_BIND="tab:down,btab:up"
PROMPT='  '
PREVIEW="tmux list-panes -t {} -aF '#S-  #I:#W:#P   #T #{window_active}:#{pane_active}' | grep {}- | cut -d ' ' -f 2-"

if [ $# -eq 1 ]; then # argument provided
	zoxide query "$1" &>/dev/null
	ZOXIDE_RESULT_EXIT_CODE=$?
	if [ $ZOXIDE_RESULT_EXIT_CODE -eq 0 ]; then # zoxide result found
		RESULT=$(zoxide query "$1")
	else # no zoxide result found
		ls "$1" &>/dev/null
		LS_EXIT_CODE=$?
		if [ $LS_EXIT_CODE -eq 0 ]; then # directory found
			RESULT=$1
		else # no directory found
			echo "No directory found."
			exit 1
		fi
	fi
else # argument not provided
	case $T_RUNTYPE in
	attached)
		RESULT=$(
			(get_fzf_results) | fzf-tmux \
				--bind "$FIND_BIND" \
				--bind "$SESSION_BIND" \
				--bind "$TAB_BIND" \
				--bind "$ZOXIDE_BIND" \
				--border-label "$BORDER_LABEL" \
				--header "$HEADER" \
				--no-sort \
				--prompt "$PROMPT" \
				--preview "$PREVIEW" \
				"$FZF_TMUX_OPTS"
		)
		;;
	detached)
		RESULT=$(
			(get_fzf_results) | fzf \
				--bind "$FIND_BIND" \
				--bind "$SESSION_BIND" \
				--bind "$TAB_BIND" \
				--bind "$ZOXIDE_BIND" \
				--border \
				--border-label "$BORDER_LABEL" \
				--header "$HEADER" \
				--no-sort \
				--preview "$PREVIEW" \
				--prompt "$PROMPT"
		)
		;;
	serverless)
		RESULT=$(
			(get_fzf_results) | fzf \
				--bind "$FIND_BIND" \
				--bind "$TAB_BIND" \
				--bind "$ZOXIDE_BIND" \
				--border \
				--border-label "$BORDER_LABEL" \
				--header " ^x zoxide ^f find" \
				--no-sort \
				--preview "$PREVIEW" \
				--prompt "$PROMPT"
		)
		;;
	esac
fi

if [ "$RESULT" = "" ]; then # no result
	exit 0                     # exit silently
fi

if [ $HOME_SED_SAFE -eq 0 ]; then
	RESULT=$(echo "$RESULT" | sed -e "s|^~/|$HOME/|") # get real home path back
fi

zoxide add "$RESULT" &>/dev/null # add to zoxide database

if [[ $RESULT != /* ]]; then # not folder path from zoxide result
	SESSION_NAME=$RESULT
else
	SESSION_NAME=$(basename "$RESULT" | tr ' .:' '_')
fi

if [ "$T_RUNTYPE" != "serverless" ]; then
	SESSION=$(tmux list-sessions -F '#S' | grep "^$SESSION_NAME$") # find existing session
fi

if [ "$SESSION" = "" ]; then # session is missing
	SESSION="$SESSION_NAME"
	if [ -e "$RESULT"/.tmuxinator.yml ]; then
		cd "$RESULT" && tmuxinator local
	elif [ -e "$HOME/.config/tmuxinator/$SESSION.yml" ]; then
		tmuxinator "$SESSION"
	else
		tmux new-session -d -s "$SESSION" -c "$RESULT" # create session
	fi
fi

case $T_RUNTYPE in # attach to session
attached)
	tmux switch-client -t "$SESSION"
	;;
detached) ;&
serverless)
	tmux attach -t "$SESSION"
	;;
esac
