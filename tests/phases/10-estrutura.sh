#!/usr/bin/env bash
# tests/phases/10-estrutura.sh — FASE 1: o workspace 2.0 e os moradores
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 1 · ESTRUTURA — o workspace crates/ e a casa ──"

# ── o workspace unificado (a fundação da diretriz) ──
for crate in elite-core elite-daemon craft-dock-rs craft-bar-rs craft-dump-rs craft-tools; do
    file_exists "workspace: crates/$crate mora na casa" "crates/$crate/Cargo.toml"
done
file_has "workspace: os 6 membros no Cargo.toml (2.0: as ferramentas nativas entraram)" "crates/Cargo.toml" 'members = ["elite-core", "elite-daemon", "craft-dock-rs", "craft-bar-rs", "craft-dump-rs", "craft-tools"]'
file_exists "elite-core: os contratos tipados + IPC + persistência" "crates/elite-core/src/lib.rs"
file_exists "elite-core: o protocolo do bus.sock" "crates/elite-core/src/ipc.rs"
file_exists "elite-core: a persistência atômica" "crates/elite-core/src/persist.rs"
file_exists "craft-dump-rs: o núcleo puro da telemetria v2" "crates/craft-dump-rs/src/lib.rs"
file_absent "o vendor/rust aposenta (a morada é crates/)" "vendor/rust"

# ── os módulos gráficos falam a fundação (a pele única) ──
file_has "barra: a pele é a folha mestra do elite-core" "crates/craft-bar-rs/src/ui.rs" 'elite_core::THEME_CSS'
file_has "dock: a pele é a folha mestra do elite-core" "crates/craft-dock-rs/src/ui.rs" 'elite_core::THEME_CSS'
file_has "dock: os pins nascem pela persistência atômica do elite-core" "crates/craft-dock-rs/src/ui.rs" 'elite_core::persist::write_atomic'
file_has "design system: os tokens da paleta no papel único" "crates/elite-core/assets/theme.css" '@define-color elite-bg'
file_has "design system: a barra na folha" "crates/elite-core/assets/theme.css" '#barwindow'
file_has "design system: a dock na folha" "crates/elite-core/assets/theme.css" '#dockbox'
file_has "design system: os popovers nativos na folha" "crates/elite-core/assets/theme.css" 'popover > contents'
file_hasnt "design system: a era waybar não volta na pele" "crates/elite-core/assets/theme.css" 'waybar'

# ── o bus.sock é o fio da casa ──
file_has "elite-core: o caminho do bus é /run/user/\$UID/elite/bus.sock" "crates/elite-core/src/lib.rs" 'elite/bus.sock'
file_has "elite-core: o quadro tem teto (FRAME_MAX)" "crates/elite-core/src/ipc.rs" 'FRAME_MAX'

# ── os bins da casa (o que sobe na sessão) ──
# (os bins RUST não moram no airootfs — nascem do cargo NO build do
# pacote; os contratos deles moram no molde abaixo)
# 2.0 Fase 2 — OS BINS COMPILADOS não moram no airootfs (nascem do cargo
# NO build do pacote: craft-update/craft-clean/craft-help/craft-pick — as
# janelas nativas da diretriz — e o craft-dump v2, a telemetria que usa o
# NOME da casa de sempre); os MOTORES shell renomeados ficam na árvore
for bin in elite-dose elite-clean craft-wake-guard craft-lock craft-game craft-shot craft-idle craft-appimage craft-display craft-rollback elite-post-upgrade elite-install-stage elite-tune elite-update; do
    file_exists "bin da casa: $bin presente" "elite/airootfs/usr/local/bin/$bin"
done
# a família RUST OBRIGATÓRIA no molde (a fundação 2.0 no pacote):
file_has "mold: a família rust OBRIGATÓRIA no install (daemon/dock/bar)" ".ci/build.sh" 'for b in elite-daemon craft-dock-rs craft-bar-rs; do'
file_has "mold: a telemetria v2 compila (craft-dump-rs)" ".ci/build.sh" '-p craft-dump-rs'
file_has "mold: as ferramentas nativas compilam (craft-tools)" ".ci/build.sh" '-p craft-tools'
file_has "mold: as ferramentas + o juiz + a telemetria v2 instalam com o nome da casa" ".ci/build.sh" 'for b in craft-update craft-clean craft-help craft-pick craft-dump craft-audit; do'
# 2.0 Fase 2 — O C DO TOPLEVEL MORREU: nenhuma fonte vendada, nenhum pacote
file_hasnt "mold: o C do toplevel não volta (a fonte vendada morreu)" ".ci/build.sh" 'craft-toplevel.c'
file_absent "vendor: o C de 3 gerações saiu do repo" "vendor/craft-toplevel.c"
# 2.0 — os bins compilados saíram do overlay (a esteira Rust manda)
for bin in craft-update craft-clean craft-help craft-audit craft-dump; do
    file_absent "bin compilado: $bin não mora no overlay (nasce do cargo)" "elite/airootfs/usr/local/bin/$bin"
done
for fossil in craft-bars craft-connect craft-audio craft-pin-pick craft-dock-gui craft-menu craft-menu-dismiss craft-player craft-power craft-logout craft-drawer craft-audio-route; do
    file_absent "fóssil aposentado ausente da árvore: $fossil" "elite/airootfs/usr/local/bin/$fossil"
done

# ── os esqueletos das Fases 2/3 (nomeados, nunca escondidos) ──
file_exists "session_smoke: o contrato da sessão viva nomeado" "tests/session_smoke/README.md"
file_exists "iso-qemu: o contrato da ISO booted nomeado" "tests/iso-qemu/README.md"

# ── o E41 (a lei do bump no mesmo commit) — o pkgrel do MOLDE elite-system ──
pkgrel="$(grep -B2 "pkgdesc='O sistema da Elite" .ci/build.sh | grep -oE 'pkgrel=[0-9]+' | head -1 | cut -d= -f2)"
if [ -n "$pkgrel" ] && [ "$pkgrel" -ge 88 ]; then
    t_ok "E41: pkgrel da era nativa ($pkgrel ≥ 88 — a dose 2.0 avançou)"
else
    t_fail "E41: pkgrel da era nativa" "pkgrel='$pkgrel' (< 88)"
fi

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase10.txt"
exit 0
