<div align = "center">

<h1><a href="https://github.com/2kabhishek/tmux-tea">tmux-tea</a></h1>

<a href="https://github.com/2KAbhishek/tmux-tea/blob/main/LICENSE">
<img alt="License" src="https://img.shields.io/github/license/2kabhishek/tmux-tea?style=flat&color=eee&label="> </a>

<a href="https://github.com/2KAbhishek/tmux-tea/graphs/contributors">
<img alt="People" src="https://img.shields.io/github/contributors/2kabhishek/tmux-tea?style=flat&color=ffaaf2&label=People"> </a>

<a href="https://github.com/2KAbhishek/tmux-tea/stargazers">
<img alt="Stars" src="https://img.shields.io/github/stars/2kabhishek/tmux-tea?style=flat&color=98c379&label=Stars"></a>

<a href="https://github.com/2KAbhishek/tmux-tea/network/members">
<img alt="Forks" src="https://img.shields.io/github/forks/2kabhishek/tmux-tea?style=flat&color=66a8e0&label=Forks"> </a>

<a href="https://github.com/2KAbhishek/tmux-tea/watchers">
<img alt="Watches" src="https://img.shields.io/github/watchers/2kabhishek/tmux-tea?style=flat&color=f5d08b&label=Watches"> </a>

<a href="https://github.com/2KAbhishek/tmux-tea/pulse">
<img alt="Last Updated" src="https://img.shields.io/github/last-commit/2kabhishek/tmux-tea?style=flat&color=e06c75&label="> </a>

<h3>tmux sessions as easy as tea ☕🪟</h3>

<figure>
  <img src="images/screenshot.png" alt="tmux-tea in action">
  <br/>
  <figcaption>tmux-tea in action</figcaption>
</figure>

</div>

tmux-tea is a tmux session manager aimed at simplifying and speeding up how you interact with tmux sessions.
It's a one key solution to all your tmux session needs.

## ✨ Features

- **Fuzzy Search**: Integrations with fzf for intuitive session selection
- **Smart Session Management**: Integrations with tmuxinator for session specific configs
- **Session Previews**: Visual previews of existing sessions and directory contents
- **Zoxide Integration**: Directory-based session creation with smart directory jumping
- **Multiple Session Support**: Open multiple sessions at once by passing multiple arguments

## Setup

### ⚡ Requirements

- tmux, fd, fzf, zoxide (required)
- tmuxinator (for session layouts)
- eza (for directory previews)

### 🚀 Installation

Add the following to your `~/.tmux.conf`

```bash
set -g @plugin '2kabhishek/tmux-tea'
```

```bash
cd ~/.tmux/plugins/tmux-tea # replace ~/.tmux/plugins with your plugin installation path
ln -sfnv $PWD/bin/tea.sh  ~/.local/bin/tea # Add tea to $PATH, make sure ~/.local/bin is in your $PATH
```

### 💻 Usage

#### Command Line Usage

```bash
# Get help
tea --help

# Interactive mode with fzf
tea

# Single session
tea ~/Projects/myapp

# Multiple sessions
tea work personal ~/Projects/app1 ~/Projects/app2

# Mix paths and zoxide queries
tea ~/code/frontend backend-service ~/docs
```

#### Tmux Key Bindings

- `<prefix> + t` - Open tea (configurable with `@tea-bind`)
- <kbd>Ctrl</kbd>+<kbd>t</kbd> - Alternate binding (configurable with `@tea-alt-bind`, set to `"false"` to disable)

#### Interactive Mode Keybindings

- <kbd>Ctrl</kbd>+<kbd>f</kbd> - Directory mode (find directories)
- <kbd>Ctrl</kbd>+<kbd>j</kbd> - Zoxide mode (recent directories)
- <kbd>Ctrl</kbd>+<kbd>s</kbd> - Session mode (existing sessions)
- <kbd>Ctrl</kbd>+<kbd>w</kbd> - Window mode (existing windows)
- <kbd>Ctrl</kbd>+<kbd>x</kbd> - Kill mode (delete sessions)
- <kbd>Ctrl</kbd>+<kbd>t</kbd> - Toggle tea / exit

### ⚙️ Configuration

All configuration options have sensible defaults and can be customized via tmux options.

#### tmuxinator integration

If you have a `.tmuxinator.yml` file in your directory, tea will use it for setting up your session.

If you have a tmuxinator config file in `~/.config/tmuxinator/` that has the same name as your tmux session directory then that will be used.

If none of these are present a tmux session is created from scratch.

#### default command

If there is no tmuxinator config present, you can set a default command to run in the session using:

```tmux
set -g @tea-default-command "$EDITOR"
```

This will open every new session after the initial one with your "$EDITOR" command running.

#### zsh integration

If you use zsh you can add the `<C-t>` binding outside tmux as well using this sni[[ed]]

```bash
bindkey -s '^T' ' tea^M ^M'
```

#### show nth parts of the path

You can set `tea-show-nth` option to show parts of the path, default is to show the last two dirs.

```tmux
# shows the second last (-2) and the last (-1) directories
set -g @tea-show-nth "-2,-1"
# if you want to show the last three directories
set -g @tea-show-nth "-3,-2,-1"
```

#### full session names

You can set the session name to be the full path you select instead of the directory using:

```tmux
set -g @tea-session-name "full-path"
```

#### preview position

You can set the **preview position** to "top","bottom","left", or "right", default is "top".

```tmux
set -g @tea-preview-position "bottom"
```

#### input position

You can set the **input position** to "default", "reverse" or "reverse-list", default is "reverse".

```tmux
set -g @tea-layout "reverse"
```

#### default directory for find mode

Set the default directory used by the find mode, first fallback is `$HOME/Projects`, second fallback is `$HOME`.

```tmux
set -g @tea-find-path "$HOME/Projects"
# You can also set it to the parent directory of PWD
set -g @tea-find-path "$PWD/.."
```

#### max depth for find mode

Set the max depth used by the find mode, default depth is "2".

```tmux
set -g @tea-max-depth "3"
```

## Behind The Code

### 🌈 Inspiration

tmux-tea was inspired by [t-smart-tmux-session-manager](https://github.com/joshmedeski/t-smart-tmux-session-manager) and shares a lot of code.

I wanted to add some more features that diverged from the original repo and wanted to keep the configs simpler.

### 💡 Challenges/Learnings

- Figuring out the preview script was quite tricky.
- Bash shenanigans!

### 🧰 Tooling

- [dots2k](https://github.com/2kabhishek/dots2k) — Dev Environment
- [nvim2k](https://github.com/2kabhishek/nvim2k) — Personalized Editor
- [sway2k](https://github.com/2kabhishek/sway2k) — Desktop Environment
- [qute2k](https://github.com/2kabhishek/qute2k) — Personalized Browser

### 🔍 More Info

- [tmux-tilit](https://github.com/2kabhishek/tmux-tilit) — Turns tmux into a terminal window manager
- [tmux2k](https://github.com/2kabhishek/tmux2k) — Makes your tmux statusbar pretty!

<hr>

<div align="center">

<strong>⭐ hit the star button if you found this useful ⭐</strong><br>

<a href="https://github.com/2KAbhishek/tmux-tea">Source</a>
| <a href="https://2kabhishek.github.io/blog" target="_blank">Blog </a>
| <a href="https://twitter.com/2kabhishek" target="_blank">Twitter </a>
| <a href="https://linkedin.com/in/2kabhishek" target="_blank">LinkedIn </a>
| <a href="https://2kabhishek.github.io/links" target="_blank">More Links </a>
| <a href="https://2kabhishek.github.io/projects" target="_blank">Other Projects </a>

</div>
