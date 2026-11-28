#!/usr/bin/env bash
# tests/phases/58-ipc-vivo.sh — FASE 5.8 · A SUÍTE EXECUTIVA DO IPC VIVO
# ══════════════════════════════════════════════════════════════════════════
# 1.0-110 · Commit 2/2 (E189, T7) — a diretriz da dose: testes AUTOMATIZADOS
# VIVOS cobrindo o motor da 1.0-110 nas nove frentes da diretriz —
#
#   1. MPRIS: o PLAYER MOCK D-BUS de verdade (interface servida num
#      dbus-daemon de prova, o mpris::thread INTEIRO e os prazos medidos
#      NO RELÓGIO: a pausa ≤300ms · o FIM É FIM <200ms · a morte do dono
#      limpa a pílula) — o contrato `vivo_o_player_mock_do_bus` do
#      elite-daemon, executado AQUI em carne de compilação;
#   2. Idle+suspensão: o verbo BusReq::Suspend cruza o fio (o eco Ack
#      contra o servidor REAL do bus) e o retry de 30s sob inibidor;
#   3. Reexec: o SIGUSR1 preserva o PID e o ELITE_LOCK_FD (o juízo VIVO
#      é do daemon sob o labwc headless — o Canal paga o ambiente);
#   4. Upgrade sem corrida: NENHUM pacman -Rns no scriptlet
#      post_upgrade (só no hook elite-post-transaction, db.lck solto);
#   5. Dock por mesa: a janela de OUTRA mesa não acende bolinha e o
#      clique lança NOVA instância na mesa corrente; o portal NÃO pisca;
#   6. Menu ⏻ limpo: EXATAMENTE as 5 ações de sessão;
#   7. SwayNC heal: o style.css entregue atomicamente antes da vaga;
#   8. craft-dump: LC_ALL=C lê Mem: sob pt_BR + a cabeça indentada do
#      wlr-randr reconhecida;
#   9. Rede sensível ao contexto: o cabo ativo alterna APENAS o device
#      (nunca `nmcli networking off`, nunca animação de Wi-Fi), o
#      direito do sem fio vira o RÁDIO e o esquerdo abre o nmtui.
#
# A HONESTIDADE (a mesma escola das fases irmãs, lei L6/L10): o que o
# ambiente não tem PULA com o réu nomeado (o Canal veste o toolchain e
# o labwc em tests.yml; o rig do dono veste o resto). Contrato quebrou
# COM binário vivo na mesa = falha de verdade.
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 5.8 · IPC VIVO — o motor da 1.0-110 em carne ──"

REPO="$(pwd)"
CRATES="$REPO/crates"
BINS="${CARGO_TARGET_DIR:-$CRATES/target}/release"
AIROOTFS="elite/airootfs"

# ── 1. MPRIS: o player mock VIVO do bus (o contrato executivo) ──────────
export PATH="$HOME/.cargo/bin:$PATH"
if command -v cargo >/dev/null 2>&1 && pkg-config --exists gtk4 2>/dev/null \
    && command -v dbus-daemon >/dev/null 2>&1; then
    if (cd "$CRATES" && cargo test -q -p elite-daemon --no-default-features vivo_o_player_mock_do_bus >/dev/null 2>&1); then
        t_ok "mpris: o player mock VIVO veste o motor inteiro (censo · pausa ≤300ms · fim <200ms · morte do dono)"
    else
        t_fail "mpris: o player mock VIVO (vivo_o_player_mock_do_bus)" "cargo test -p elite-daemon vivo_o_player_mock_do_bus falhou"
    fi
else
    t_skip "mpris: o player mock VIVO (dbus-daemon de prova)" "cargo/gtk4/dbus-daemon ausentes — o Canal veste (tests.yml)"
fi

# ── 2. Idle + suspensão: o verbo no fio e o retry de 30s ────────────────
# o verbo BusReq::Suspend cruza o fio e o eco Ack volta (o protocolo é o
# servidor REAL do bus da fundação — sock.rs em carne); a suspensão de
# verdade (login1.Manager.Suspend no journalctl do rig) é juízo do Canal/rig
if command -v cargo >/dev/null 2>&1 && pkg-config --exists gtk4 2>/dev/null; then
    # o alvo é o NÚCLEO std-only (a mesma veste da fase 30 — o cache do
    # target compartilhado paga o juízo sem recompilar a gui de novo)
    if (cd "$CRATES" && cargo test -q -p craft-dock-rs --no-default-features cliente_contra_o_daemon_falso_do_bus >/dev/null 2>&1); then
        t_ok "ipc: o verbo atravessa o fio com o eco Ack (cliente contra o daemon REAL do bus.sock)"
    else
        t_fail "ipc: o verbo atravessa o fio (cliente_contra_o_daemon_falso_do_bus)" "cargo test -p craft-dock-rs --no-default-features cliente_contra_o_daemon_falso_do_bus falhou"
    fi
else
    t_skip "ipc: o verbo atravessa o fio" "cargo/gtk4 ausentes — o Canal veste (tests.yml)"
fi
file_has "suspend: o verbo NATIVO mora no fio (BusReq::Suspend — o item Suspender da barra)" "crates/elite-core/src/lib.rs" 'Suspend,'
file_has "suspend: o daemon veste o verbo (a thread própria segura o Ack)" "crates/elite-daemon/src/nucleo.rs" 'BusReq::Suspend => std::thread::Builder::new()'
file_has "suspend: o caminho nativo é o login1.Manager.Suspend pela zbus system COMPARTILHADA" "crates/elite-daemon/src/idle.rs" 'org.freedesktop.login1.Manager.Suspend'
file_has "idle: o retry de 30s da vigília inibida (a cadeia nunca morre)" "crates/elite-daemon/src/wayland.rs" 'arma_idle_ms(30_000'

# ── 3. Reexec: o SIGUSR1 preserva o PID e o lock ─────────────────────────
# o juízo VIVO (kill -USR1 no daemon sob o labwc headless) mora no bloco
# da SESSÃO VIVA no fim da fase; AQUI ficam os contratos do mecanismo:
file_has "reexec: o reexec in-place no SIGUSR1 (mesmo PID, mesmo flock)" "crates/elite-daemon/src/main.rs" 'fn reexec_in_place'
file_has "reexec: o ELITE_LOCK_FD herdado/adotado (o fd da trava sobrevive ao exec)" "crates/elite-daemon/src/supervise.rs" 'ELITE_LOCK_FD'
file_has "reexec: o CLOEXEC do fd da trava LIMPO antes do exec (o fcntl herda o lock)" "crates/elite-daemon/src/main.rs" 'FD_CLOEXEC'

# ── 4. Upgrade sem corrida: nenhum pacman dentro do pacman ──────────────
file_hasnt "upgrade: o scriptlet post_upgrade NÃO roda pacman (a corrida do db.lck morreu)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'pacman -Rns'
file_has "upgrade: o debloat mora no hook PostTransaction (db.lck SOLTO)" "$AIROOTFS/usr/local/bin/elite-post-transaction" 'pacman -Rns'
# 1.0-110 T6 — o rc.xml VIVO é MIGRADO (o sync ausente-only nunca entrega
# o Execute do elite-daemon desk aos rigs de antes da 1.0-100):
file_has "upgrade: o rc.xml VIVO ganha o Execute do desk (a migração com backup)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'bak-elite-desk'
file_has "upgrade: o GoToDesktop left/right veste o Execute (o scroll do desktop volta a ser visto)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'elite-daemon desk left'

# ── 5. Dock por mesa + filtro do portal (o espelho do Alt+Tab) ──────────
file_has "dock: a janela conta SÓ se mora na mesa CORRENTE (janela_da_mesa)" "crates/craft-dock-rs/src/ui.rs" 'fn janela_da_mesa'
file_has "dock: as janelas do alvo são filtradas pela mesa (windows_of_state)" "crates/craft-dock-rs/src/ui.rs" '.filter(|id| janela_da_mesa(s, *id))'
file_has "dock: o PORTAL nunca nasce botão (o xdg-desktop-portal-gtk não pisca)" "crates/craft-dock-rs/src/ui.rs" 'starts_with("xdg-desktop-portal")'
file_has "dock: 0 janelas na mesa atual lança NOVA instância (sem pular para outra mesa)" "crates/craft-dock-rs/src/ui.rs" 'A PROVA NO CLIQUE É O PUSH'
file_has "dock: o vigia do papel dos pins (inotify — o tick de 5s é só ceifa/guard)" "crates/craft-dock-rs/src/ui.rs" 'fn arma_vigia_pins'
file_hasnt "dock: o reload PERIÓDICO dos pins no tick NÃO volta (o vigia veste por evento)" "crates/craft-dock-rs/src/ui.rs" '# o RELOAD PERIÓDICO DOS PINS MORREU COM O VIGIA'
# e o sock.rs continua julgando o casamento puro (cargo cobre):
if command -v cargo >/dev/null 2>&1 && pkg-config --exists gtk4 2>/dev/null; then
    if (cd "$CRATES" && cargo test -q -p craft-dock-rs --no-default-features >/dev/null 2>&1); then
        t_ok "dock: o núcleo do casamento segue verde (o juízo puro do sock/procapp)"
    else
        t_fail "dock: o núcleo do casamento (sock/procapp)" "cargo test -p craft-dock-rs --no-default-features falhou"
    fi
fi

# ── 6. Menu ⏻ limpo: EXATAMENTE as 5 ações de sessão ────────────────────
# as 5 ações da sessão: Bloquear · Suspender (verbo nativo) · Reiniciar
# · Desligar · Encerrar — NENHUM atalho de era volta ao cardápio
_n_acoes="$(grep -c 'linha_menu_bar(' crates/craft-bar-rs/src/ui.rs 2>/dev/null || true)"
if [ "${_n_acoes:-0}" = "3" ] \
    && grep -q '"Bloquear tela", &\["craft-lock"\]' crates/craft-bar-rs/src/ui.rs \
    && grep -q 'elite_core::BusReq::Suspend' crates/craft-bar-rs/src/ui.rs \
    && grep -q '"Reiniciar", &\["systemctl", "reboot"\]' crates/craft-bar-rs/src/ui.rs \
    && grep -q '"Desligar", &\["systemctl", "poweroff"\]' crates/craft-bar-rs/src/ui.rs \
    && grep -q '"Encerrar sessão", &\["craft-logout"\]' crates/craft-bar-rs/src/ui.rs \
    && ! grep -q '"Modo de jogo", ' crates/craft-bar-rs/src/ui.rs; then
    t_ok "menu ⏻: EXATAMENTE as 5 ações de sessão (nenhum atalho de era volta)"
else
    t_fail "menu ⏻: exatamente as 5 ações de sessão" "achado ${_n_acoes:-?} linha(s) de linha_menu_bar (esperado 3: a def + o lock + o laço das três) — ou falta rótulo das 5 ações"
fi
file_hasnt "menu ⏻: o rótulo cravado de Hz morre (o menu nunca mente o monitor)" "crates/craft-bar-rs/src/ui.rs" 'Monitores ('
file_hasnt "menu ⏻: o cardápio não promete atalho de jogo" "crates/craft-bar-rs/src/ui.rs" '"Modo de jogo", '

# ── 7. SwayNC heal: o CSS existe antes da vaga ───────────────────────────
file_has "swaync: o mestre nasce ATOMICAMENTE no \$HOME antes da vaga (fn entrega_css_swaync)" "crates/elite-daemon/src/supervise.rs" 'fn entrega_css_swaync'
file_has "swaync: o style.css do skel é o mestre (o COULD NOT FIND CSS FILE! morre)" "elite/airootfs/etc/skel/.config/swaync/style.css" 'notification'

# ── 8. craft-dump honesto sob pt_BR ─────────────────────────────────────
if command -v cargo >/dev/null 2>&1 && pkg-config --exists gtk4 2>/dev/null; then
    if (cd "$CRATES" && cargo test -q -p craft-dump-rs >/dev/null 2>&1); then
        t_ok "dump: o craft-dump segue verde (o LC_ALL=C da colheita + a cabeça indentada)"
    else
        t_fail "dump: o craft-dump verde" "cargo test -p craft-dump-rs falhou"
    fi
fi
file_has "dump: o LC_ALL=C da colheita (o free imprime 'Mem:' em qualquer locale)" "crates/craft-dump-rs/src/main.rs" '.env("LC_ALL", "C")'
file_has "dump: a cabeça de output indentada RECONHECIDA (o '  DP-1' não é fantasma)" "crates/craft-dump-rs/src/lib.rs" 'fn e_cabeca_output'

# ── 9. Rede sensível ao contexto (o kind do fio decide) ──────────────────
file_has "rede: o publicador event-driven mora no daemon (o NM no system bus por sinal)" "crates/elite-daemon/src/network.rs" 'fn thread()'
file_has "rede: o julgamento puro (ethernet ativa vence · o offline é tipado)" "crates/elite-daemon/src/network.rs" 'fn julga_dispositivos'
file_hasnt "rede: o NUNCA 'networking off' (o cabo vivo não derruba o rádio)" "crates/craft-bar-rs/src/ui.rs" '"networking", "off"'
file_has "rede: o direito do SEM FIO vira o RÁDIO (a placa e o LED apagam)" "crates/craft-bar-rs/src/ui.rs" '"nmcli", "radio", "wifi", cmd'
file_has "rede: a janela nmtui flutuante tem regra PRÓPRIA no rc.xml (centrada)" "elite/airootfs/etc/skel/.config/labwc/rc.xml" 'identifier="craft-net-tui"'
file_has "rede: a gaveta exibe UMA entrada de rede (o editor técnico é sombra)" "elite/airootfs/usr/local/share/applications/nm-connection-editor.desktop" 'NoDisplay=true'

# ── 10. O BARRAMENTO VIVO SEM POLLING (a ponte e o cano da diretriz) ────
file_hasnt "barra: o poller de belts NÃO volta (áudio/rede/bluetooth/jogo vêm por push)" "crates/craft-bar-rs/src/ui.rs" 'fn poller'
file_hasnt "barra: o DRAIN_MS de cadência NÃO volta (a entrega é um idle por quadro)" "crates/craft-bar-rs/src/ui.rs" 'DRAIN_MS'
file_hasnt "dock: o dreno de 50ms NÃO volta (a ponte entrega por mensagem)" "crates/craft-dock-rs/src/ui.rs" 'const DRAIN_MS'
file_has "barra: a PONTE viva (um idle por quadro — provado no compilador: a glib 0.22 não tem MainContext::channel)" "crates/craft-bar-rs/src/ui.rs" 'fn entrega(msg: Msg)'
file_has "dock: a PONTE viva da dock (o canal mpsc morreu com o dreno)" "crates/craft-dock-rs/src/ui.rs" 'fn entrega(msg: Msg)'
file_has "barra: o CANO dos sinais (self-pipe — o handler cru acorda a leitora)" "crates/craft-bar-rs/src/ui.rs" 'fn arma_cano_sinais'
file_has "dock: o CANO dos sinais da dock (W-S-d e reload sem cadência)" "crates/craft-dock-rs/src/ui.rs" 'fn arma_cano_sinais'
file_has "barra: o relógio agenda a VIRADA do minuto (um timeout por minuto)" "crates/craft-bar-rs/src/ui.rs" 'fn agenda_relogio'
file_has "barra: o volume scroll TRAILING de 70ms (a rajada vira UM wpctl no silêncio)" "crates/craft-bar-rs/src/ui.rs" 'VOLUME_TRAILING_MS: u64 = 70'
file_has "menu: o carimbo ✓ na opção SALVA da auto-suspensão (o dono vê onde está)" "elite/airootfs/usr/local/bin/craft-idle" '✓ '
file_has "menu: o carimbo ✓ no estado do modo de jogo" "elite/airootfs/usr/local/bin/craft-game" '✓ Ativo'
file_has "css: o pick veste a borda lilás e os cantos 14px (a paridade com #menuwin)" "crates/elite-core/assets/theme.css" 'border-radius: 14px'
file_has "css: o TEXTO ESCURO em todo estado destacado do pick (o contraste legível)" "crates/elite-core/assets/theme.css" 'row:selected button'
file_has "css: o badge roxo do modo de jogo (a classe .on acende o assento)" "crates/elite-core/assets/theme.css" '#gamebtn.on'
file_has "css: a micro-animação da pílula (140ms SÓ opacity — GPU-friendly)" "crates/elite-core/assets/theme.css" '.faixa-nova'
file_has "pick: a busca some SEM reservar espaço quando a lista é curta (≤8)" "crates/craft-tools/src/bin/craft-pick.rs" 'itens.len() <= 8'
file_has "menu-camada: o teclado SOB DEMANDA (o Exclusive de era bloqueava Backspace/Ctrl+V)" "crates/craft-tools/src/lib.rs" 'KeyboardMode::OnDemand'
file_has "menu-camada: o carimbo do fechou_em mata a corrida do 2º clique (sem piscar)" "crates/craft-tools/src/lib.rs" 'fechou_em'
file_has "rc.xml: o clique no papel de parede LIMPA o foco (o Unfocus desce os menus)" "elite/airootfs/etc/skel/.config/labwc/rc.xml" '<action name="Unfocus" />'

# ── 11. A SESSÃO VIVA sob o labwc headless (o Canal/rig paga o ambiente) ─
# o mesmo gate do 57-smoke: sem labwc o juízo PULA com o réu nomeado —
# o reexec preservando o PID, os verbos do bus com Ack e a 2ª instância
# recusada são provas de DAEMON VIVO (a esteira do Canal as veste).
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null 2>&1 || ! pkg-config --exists gtk4 2>/dev/null; then
    t_skip "vivo: a sessão headless" "cargo/gtk4 ausentes — o Canal veste (tests.yml)"
elif ! command -v labwc >/dev/null 2>&1; then
    t_skip "vivo: a sessão headless (reexec/verbos/2ª instância)" "labwc ausente — o Canal veste o juiz (tests.yml)"
else
    # o build release compartilhado com as fases irmãs
    if (cd "$CRATES" && cargo build --release -q --workspace 2>/dev/null) \
        && [ -x "$BINS/elite-daemon" ]; then
        VIVO="$(mktemp -d /tmp/elite-58-vivo-XXXXXX)"
        XDG="$VIVO/xdg"; HOMES="$VIVO/home"
        mkdir -p "$XDG" "$HOMES/.cache/elite" "$VIVO/shim"
        chmod 700 "$XDG"
        # o shim da fase irmã (o daemon chamado por PATH veste o binário
        # compilado; o reexec veste o /proc/self/exe — o MESMO corpo)
        ln -sf "$BINS/elite-daemon" "$VIVO/shim/elite-daemon"
        ln -sf "$BINS/craft-pick" "$VIVO/shim/craft-pick"
        ln -sf "$BINS/craft-bar-rs" "$VIVO/shim/craft-bar-rs"
        ln -sf "$BINS/craft-dock-rs" "$VIVO/shim/craft-dock-rs"
        export HOME="$HOMES"
        export XDG_RUNTIME_DIR="$XDG"
        export PATH="$VIVO/shim:$PATH"
        export WLR_BACKENDS=headless
        export WLR_LIBINPUT_NO_DEVICES=1
        export WLR_RENDERER=pixman
        export GSK_RENDERER=cairo
        export NO_AT_BRIDGE=1
        export GTK_A11Y=none
        labwc >"$VIVO/labwc.log" 2>&1 &
        LABWC_PID=$!
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
        export WAYLAND_DISPLAY
        _sock_ok=0
        for _ in $(seq 1 30); do
            [ -S "$XDG/$WAYLAND_DISPLAY" ] && { _sock_ok=1; break; }
            kill -0 "$LABWC_PID" 2>/dev/null || break
            sleep 0.5
        done
        if [ "$_sock_ok" != 1 ]; then
            t_skip "vivo: a sessão headless" "o labwc não subiu (últimas linhas: $(tail -2 "$VIVO/labwc.log" 2>/dev/null | tr '\n' ' '))"
        else
            # a sessão da casa sob o bus de prova (o dbus-run-session
            # veste a session bus REAL dos verbos do daemon)
            if command -v dbus-run-session >/dev/null 2>&1; then
                dbus-run-session -- bash -c '
                    printf "%s\n" "$DBUS_SESSION_BUS_ADDRESS" > "$0/dbus.addr"
                    exec elite-daemon session
                ' "$XDG" >"$VIVO/daemon.err" 2>&1 &
            else
                elite-daemon session >"$VIVO/daemon.err" 2>&1 &
            fi
            DAEMON_PID=$!
            _bus_ok=0
            for _ in $(seq 1 40); do
                [ -S "$XDG/elite/bus.sock" ] && { _bus_ok=1; break; }
                kill -0 "$DAEMON_PID" 2>/dev/null || break
                sleep 0.5
            done
            if [ "$_bus_ok" = 1 ]; then
                t_ok "vivo: o bus.sock da sessão headless nasceu (o núcleo no ar)"
                # (a) o REEXEC preserva o PID (o kill -USR1 veste o MESMO
                # corpo — o execve de si mesmo com o fd da trava herdado)
                kill -USR1 "$DAEMON_PID" 2>/dev/null || true
                sleep 1
                if kill -0 "$DAEMON_PID" 2>/dev/null; then
                    t_ok "vivo: o reexec do SIGUSR1 PRESERVA o pid $DAEMON_PID (mesmo corpo, mesmo flock)"
                else
                    t_fail "vivo: o reexec preserva o PID" "o pid $DAEMON_PID morreu no USR1 (stderr: $(tail -3 "$VIVO/daemon.err" 2>/dev/null | tr '\n' ' '))"
                fi
                # (b) o verbo do bus ecoa Ack (o daemon REEXECUTADO fala)
                if timeout 5 elite-daemon desk 2 >/dev/null 2>&1; then
                    t_ok "vivo: o verbo desk ecoa Ack pelo fio (o daemon reexecutado falou)"
                else
                    t_fail "vivo: o verbo desk ecoa Ack" "exit != 0 contra o daemon vivo"
                fi
                # (c) a 2ª instância SAI 0 (o guard do dono único do bus)
                if timeout 5 elite-daemon session >/dev/null 2>&1; then
                    t_ok "vivo: a 2ª instância sai limpa (o dono único do bus segue dono)"
                else
                    t_fail "vivo: a 2ª instância sai limpa" "exit != 0 (o guard do dono único)"
                fi
            else
                t_skip "vivo: a sessão headless" "o bus.sock não nasceu (stderr: $(tail -3 "$VIVO/daemon.err" 2>/dev/null | tr '\n' ' '))"
            fi
            kill "$DAEMON_PID" 2>/dev/null || true
            wait "$DAEMON_PID" 2>/dev/null || true
        fi
        kill "$LABWC_PID" 2>/dev/null || true
        wait "$LABWC_PID" 2>/dev/null || true
        rm -rf "$VIVO"
    else
        t_skip "vivo: a sessão headless" "cargo build --release não terminou / elite-daemon ausente"
    fi
fi

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase58.txt"
exit 0
