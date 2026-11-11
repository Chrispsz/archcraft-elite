# ═══════════════════════════════════════════════════════════════════════════
# Archcraft ELITE · 10-elite-defaults.sh — OS APPS PADRÃO COMO VARIÁVEIS
# (E103 — a abstração XDG da missão do dono)
# ═══════════════════════════════════════════════════════════════════════════
# A diretriz: "substituir chamadas diretas a programas específicos por
# variáveis padrão da especificação FreeDesktop/XDG nos dotfiles e menus".
# O USUÁRIO MANDA (export no próprio zshrc/profile.d dele vence — só
# preenchemos o que está vazio: a lei da variável PRESENTE não é tocada):
#   TERMINAL   → ${TERMINAL:-foot}
#   FILEMANAGER→ ${FILEMANAGER:-thunar}
#   EDITOR     → ${EDITOR:-nano} (e o VISUAL irmão)
#   BROWSER    → ${BROWSER:-brave}
# Os scripts da casa (exo-open, menus, dock) lêem estas variáveis — trocar
# o terminal da casa é export TERMINAL=alacritty, não editar menu.
# Qualquer shell de login (zsh via sddm, su, ssh) herda.
: "${TERMINAL:=foot}";      export TERMINAL
: "${FILEMANAGER:=thunar}"; export FILEMANAGER
: "${EDITOR:=nano}";        export EDITOR
: "${VISUAL:=nano}";        export VISUAL
: "${BROWSER:=brave}";      export BROWSER
