# ~/.zshrc — Archcraft ELITE (v1.0.3)
# ═══════════════════════════════════════════════════════════════════════
# zsh PURO + plugins standalone + starship — substitui o framework omz do
# stock (7.3MB de framework carregado a cada prompt) pela stack moderna
# 2026: zsh-autosuggestions + zsh-syntax-highlighting + starship (rust).
# Aliases turbinados pelos CLIs brabos da ISO: eza, bat, dust, procs,
# zoxide, ripgrep, fd, fzf.
#
# O PATH vem de /etc/zprofile; este arquivo é o único dono do shell.

# ── Histórico ─────────────────────────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE
setopt AUTO_CD INTERACTIVE_COMMENTS

# ── Rehash on-demand: instalou pacote → comando novo sem relogin ──────
# Mesma técnica do criador do Archcraft (archcraft-hooks-zsh toca
# /var/cache/zsh/pacman a cada transação do pacman).
zshcache_time="$(date +%s%N)"
autoload -Uz add-zsh-hook
rehash_precmd() {
  if [[ -a /var/cache/zsh/pacman ]]; then
    local paccache_time
    paccache_time="$(date -r /var/cache/zsh/pacman +%s%N)"
    if (( zshcache_time < paccache_time )); then
      rehash
      zshcache_time="$paccache_time"
    fi
  fi
}
add-zsh-hook -Uz precmd rehash_precmd

# ── Completion ────────────────────────────────────────────────────────
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# ── Plugins standalone (os brabos — sem framework) ────────────────────
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ── zoxide (cd inteligente: "z proj" pula pro diretório certo) ────────
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ── Prompt: starship (rust, cross-shell, ~2ms) ────────────────────────
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# ── Aliases: os CLIs brabos no lugar dos clássicos ────────────────────
# ls → eza (ícones, git status por arquivo, tree com -T)
if command -v eza >/dev/null 2>&1; then
  alias l='eza -lh --group-directories-first --icons=auto'
  alias ll='eza -lah --group-directories-first --icons=auto'
  alias la='eza -a --icons=auto'
  alias lr='eza -T --icons=auto'
  alias lg='eza -l --git --group-directories-first --icons=auto'
fi
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
command -v dust >/dev/null 2>&1 && alias du='dust'
command -v procs >/dev/null 2>&1 && alias ps='procs'

# git (atalhos do criador do Archcraft, mantidos)
alias gcl='git clone --depth 1'
alias gi='git init'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'

# sistema
alias update='sudo pacman -Syu'
alias zshconfig='mousepad ~/.zshrc'
