#!/usr/bin/env bash
# tests/phases/10-estrutura.sh — FASE 1: o workspace 2.0 e os moradores
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 1 · ESTRUTURA — o workspace crates/ e a casa ──"

# ── o workspace unificado (a fundação da diretriz) ──
for crate in elite-core elite-daemon craft-dock-rs craft-bar-rs craft-dump-rs; do
    file_exists "workspace: crates/$crate mora na casa" "crates/$crate/Cargo.toml"
done
file_has "workspace: os 5 membros no Cargo.toml" "crates/Cargo.toml" 'members = ["elite-core", "elite-daemon", "craft-dock-rs", "craft-bar-rs", "craft-dump-rs"]'
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
for bin in craft-dump craft-update craft-wake-guard craft-lock craft-game craft-shot craft-idle elite-post-upgrade elite-install-stage elite-tune craft-menu craft-menu-dismiss; do
    file_exists "bin da casa: $bin presente" "elite/airootfs/usr/local/bin/$bin"
done
# a família RUST OBRIGATÓRIA no molde (a fundação 2.0 no pacote):
file_has "mold: a família rust OBRIGATÓRIA no install (daemon/dock/bar)" ".ci/build.sh" 'for b in elite-daemon craft-dock-rs craft-bar-rs; do'
file_has "mold: a telemetria v2 compila (craft-dump-rs)" ".ci/build.sh" '-p craft-dump-rs'
file_has "mold: a telemetria v2 instala ao lado do v1" ".ci/build.sh" 'craft-dump-rs" "${{pkgdir}}/usr/local/bin/craft-dump-rs'
for fossil in craft-bars craft-connect craft-audio craft-pin-pick craft-dock-gui; do
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
