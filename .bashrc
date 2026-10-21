#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
export PATH="$HOME/.local/bin:$PATH"

alias hproxy='export http_proxy=http://127.0.0.1:10809 https_proxy=http://127.0.0.1:10809'
alias ytermusic='http_proxy=http://127.0.0.1:10809 https_proxy=http://127.0.0.1:10809 command ytermusic'

alias hycfg='nvim ~/.config/hypr/hyprland.lua'

# Dotfiles: bare repo in ~/.dotfiles, work tree = ~ (use instead of git for configs)
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

export EDITOR=nvim
export VISUAL=nvim

# yazi: `y` opens yazi; on quit (q) the shell cd's to where you ended up (Q = quit without cd)
y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# starship prompt (config: ~/.config/starship.toml)
eval "$(starship init bash)"

# zoxide: learns visited dirs; `z foo` jumps in shell, Z inside yazi
eval "$(zoxide init bash)"

eval "$(fzf --bash)"

tldrr() { tldr -L ru "$@" 2>/dev/null || tldr "$@"; }

# cmatrix paints its background ANSI black (color0); make that see-through in kitty while it runs
cmatrix() {
    printf '\e]21;transparent_background_color1=#1e2026\e\\'
    command cmatrix "$@"
    printf '\e]21;transparent_background_color1\e\\'
}

# open man pages in neovim instead of less
export MANPAGER='nvim +Man!'
  

# fastfetch greeting: only interactive kitty, once per window (not in nested shells)
if [[ $- == *i* && $TERM == xterm-kitty && -z $FASTFETCH_SHOWN ]]; then
    export FASTFETCH_SHOWN=1
    # greeting: random pixel art from ~/Pictures/pixel-art; plain `fastfetch` keeps the Arch logo
    # Re-lay the greeting out on resize (text beside the art <-> art only), but only
    # while it is the sole thing on screen: the first command disarms it. Armed
    # before the greeting is drawn: tiling resizes the window as it opens.
    __ff_art=$(pixfetch --pick)  # pinned, so redraws keep this window's picture
    __ff_cmds=0 __ff_size=$(tput cols)x$(tput lines)
    PROMPT_COMMAND="((__ff_cmds++)); ${PROMPT_COMMAND}"
    __ff_winch() {
        (( __ff_cmds <= 1 )) || return
        # let an animated resize settle: one redraw at the final size, not one per step
        local size=$(tput cols)x$(tput lines) now
        while sleep 0.06; now=$(tput cols)x$(tput lines); [[ $now != $size ]]; do size=$now; done
        [[ $size != $__ff_size ]] || return
        __ff_size=$size
        PIXFETCH_ART=$__ff_art PIXFETCH_REDRAW=1 pixfetch
        # readline does not repaint the prompt after the clear (none yet at startup)
        (( __ff_cmds )) || return 0
        local ps=${PS1@P}
        printf '%s' "${ps//[$'\001\002']/}"
    }
    trap __ff_winch WINCH
    PIXFETCH_ART=$__ff_art pixfetch
fi

# nchat: separate Telegram accounts, one config dir each
alias tg1='nchat'
alias tg2='nchat -d ~/.config/nchat-2'

# Machine-local, untracked additions
[ -f ~/.bashrc.local ] && . ~/.bashrc.local
