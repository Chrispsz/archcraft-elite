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
# v2.10.5→E136 — o editor gráfico da casa é o gnome-text-editor (W-e,
# a PARTE 2/2 do dono); no TERMINAL o nano segue sendo o da casa (este
# alias edita o próprio .zshrc sem sair do shell).
alias zshconfig='nano ~/.zshrc'

# ── elite-hello-1 · Saudação: o terminal abre com o retrato do sistema ──
# E73 (o dono: "faz o terminal abrir por padrao com aquelas paradas que
# mostra o kernel e etc"): o craft-hello (fastfetch com o logo Archcraft +
# fallback próprio) roda a cada shell interativo novo — kernel, uptime e
# pacotes na cara sem comando nenhum. Fuga honesta: export
# ELITE_NO_HELLO=1 desliga (o W-S-h usa a mesma porta pra não dobrar).
# 1.0-109 — O GUARDA TRIPLO (a diretriz da Etapa 2: scripts, pipes,
# subshells e testes da porteira NUNCA recebem saída extra): o $- julga
# o shell INTERATIVO, o [ -t 1 ] julga a saída TTY de verdade (o pipe
# e o redirecionamento calam o card) e o ELITE_NO_FETCH/ELITE_NO_HELLO
# são as fugas honestas da casa.
if [[ $- == *i* ]] && [ -t 1 ] && (( $+commands[craft-hello] )) \
   && [[ -z "${ELITE_NO_FETCH:-}" && -z "${ELITE_NO_HELLO:-}" ]]; then
  craft-hello
fi

# ── elite-verbos-2 · Os verbos da casa em português, sem decorar nada ──
# 1.0-109 (a diretriz da Etapa 2: ninguém memoriza craft-* — os verbos
# de 1 palavra abrem a ferramenta certa; a linha "Comandos rápidos" do
# craft-hello os apresenta a cada terminal).
alias ajuda='craft-help'
alias saude='craft-doctor'
alias atualizar='craft-update'
alias limpar='craft-clean'
alias rede='craft-net'
alias jogo='craft-game'
alias monitores='wdisplays'
