// ═════════════════════════════════════════════════════════════════════════
// craft-dump-rs — o NÚCLEO da telemetria v2 (2.0)
// ═════════════════════════════════════════════════════════════════════════
// O papel que se conhece: era nativa, a família de sessão esperada, a
// ausência TOTAL do legado, os serviços críticos e os parâmetros de boot.
// O núcleo é PURO (entrada = texto colhido; saída = veredito tipado) —
// testa em qualquer lugar; o main é a mão que colhe (systemctl/procfs/cmdline).
// FASE 1: os contratos e os juízos. A coleta completa (bus.sock, journal
// do PrepareForSleep) é Fase 2 — o bash craft-dump segue vivo até a v2
// cobrir os dois pés (a aposentadoria tem substituto antes de nascer).
// ═════════════════════════════════════════════════════════════════════════

/// O legado que NUNCA mais vive na casa 2.0 (processo, bin ou conf).
pub const LEGADO: &[&str] = &[
    "waybar",
    "craft-audio",       // a UI Python (o roteador era OUTRO papel — que também morreu)
    "craft-bars",        // o supervisor sh — o lançador único é elite-daemon session
    "craft-connect",     // os menus fuzzel de rede/bluetooth — iwgtk/blueman são a tela
    "craft-pin-pick",    // o picker fuzzel de pins — o popover da dock tomou o lugar
    "craft-menu",        // o painel fuzzel (2.0: o craft-pick GTK4 tomou o lugar)
    "craft-player",      // o poller de 1s — o MPRIS pelo bus tomou o lugar
    "craft-drawer",      // o wrapper sh — o nwg-drawer direto tomou o lugar
    "craft-power",       // o menu fuzzel de sessão — o popover + elite-sessao tomaram
    "craft-logout",      // o wrapper do power — idem
    "craft-menu-dismiss",// o fechar-por-pid — o GTK/labwc fecham sozinhos
    "craft-audio-route", // 2.0: o roteador Python — o audio.rs do daemon tomou
    "craft-toplevel",    // 2.0: o C de 3 gerações — o wayland.rs do daemon tomou
    "swayidle",          // 2.0: a vigília é do daemon (ext-idle-notify nativo)
];

/// A família de sessão 2.0 esperada de pé (comm).
pub const FAMILIA_SESSAO: &[&str] = &[
    "elite-daemon",   // o orquestrador único (session + game + supervise)
    "craft-dock-rs",  // a dock GTK4 nativa
    "craft-bar-rs",   // a top bar GTK4 nativa
];

/// Os serviços críticos do sistema 2.0 (o papel nomeia o ausente).
pub const SERVICOS_CRITICOS: &[&str] = &[
    "NetworkManager",
    "bluetooth",
    "coolercontrold",
    "scx_loader",
];

/// Juízo de um comm de processo contra a lista do legado.
/// EXATO (não prefixo): o réu 'craft-audio' (a UI aposentada) não pode
/// comer o 'craft-audio-route' (o roteador — tuning vivo da casa).
pub fn e_legado(comm: &str) -> bool {
    LEGADO.iter().any(|l| comm == *l)
}

/// O relatório de um serviço: presente/ausente a partir do texto do
/// `systemctl --no-legend --all list-unit-files` (cabeças de linha).
pub fn servico_presente(saida_systemctl: &str, unit: &str) -> bool {
    saida_systemctl.lines().any(|l| {
        let cabeca = l.split_whitespace().next().unwrap_or("");
        // o unit pode nascer 'coolercontrold.service' ou com o caminho cheio
        let nome = cabeca.split('/').last().unwrap_or(cabeca);
        nome == unit || nome == &format!("{unit}.service") || cabeca == &format!("{unit}.service")
    })
}

/// Juízo do kernel cmdline: o parâmetro pedido está lá (palavra inteira
/// ou com =valor — 'mitigations=off' casa, 'mitigations=100' NÃO casa).
pub fn cmdline_tem(cmdline: &str, parametro: &str) -> bool {
    cmdline.split_whitespace().any(|p| {
        p == parametro
            || p.strip_prefix(parametro)
                .map(|r| r.starts_with('='))
                .unwrap_or(false)
    })
}

/// A linha do relatório: honesta — PRESENTE/AUSENTE com o nome.
pub fn linha_servico(saida: &str, unit: &str) -> String {
    if servico_presente(saida, unit) {
        format!("serviço: {unit} PRESENTE")
    } else {
        format!("serviço: {unit} AUSENTE (o réu nomeado no papel)")
    }
}

/// Bloco de boot: os parâmetros da diretriz (o que já existe NÃO é tocado —
/// aqui só o JUÍZO; a escrita mora no elite-install-stage).
pub fn juizo_boot(cmdline: &str) -> Vec<String> {
    [
        "mitigations=off",
        "nowatchdog",
        "amdgpu.ppfeaturemask=0xffffffff",
    ]
    .iter()
    .map(|p| {
        if cmdline_tem(cmdline, p) {
            format!("boot: {p} PRESENTE")
        } else {
            format!("boot: {p} AUSENTE")
        }
    })
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn o_legado_e_nomeado_e_nada_mais() {
        for l in ["waybar", "craft-audio", "craft-bars", "craft-connect"] {
            assert!(e_legado(l), "{l} tem que ser legado");
        }
        assert!(!e_legado("craft-dock-rs"), "a dock é a casa, não legado");
        assert!(!e_legado("craft-bar-rs"), "a barra é a casa");
        assert!(!e_legado("elite-daemon"), "o daemon é a casa");
        // 2.0: o roteador python TAMBÉM aposentou (o audio.rs do daemon
        // é o roteador — a diretriz §7 na carne)
        assert!(e_legado("craft-audio-route"), "o roteador python é legado da 2.0");
    }

    #[test]
    fn servico_presente_le_o_list_unit_files_de_verdade() {
        let saida = "\
craft-dock-rs.service                        enabled         enabled
coolercontrold.service                       enabled         enabled
scx_loader.service                           enabled         enabled
NetworkManager.service                       enabled         enabled
bluetooth.service                            enabled         enabled
";
        for u in SERVICOS_CRITICOS {
            assert!(servico_presente(saida, u), "{u} presente na saída");
        }
        assert!(!servico_presente(saida, "paccache"));
        // a linha do serviço ausente vira réu nomeado
        assert!(linha_servico(saida, "coolercontrold").contains("PRESENTE"));
        assert!(linha_servico(saida, "fatorial").contains("AUSENTE"));
    }

    #[test]
    fn cmdline_julga_parametro_e_nao_prefixo_aleatorio() {
        let cmd = "quiet splash mitigations=off nowatchdog amdgpu.ppfeaturemask=0xffffffff ntsync=1";
        assert!(cmdline_tem(cmd, "mitigations=off"));
        assert!(cmdline_tem(cmd, "nowatchdog"));
        assert!(cmdline_tem(cmd, "amdgpu.ppfeaturemask"));
        assert!(cmdline_tem(cmd, "amdgpu.ppfeaturemask=0xffffffff"));
        assert!(!cmdline_tem(cmd, "mitigations=100"), "valor diferente não casa");
        assert!(!cmdline_tem(cmd, "mitigation"), "prefixo solto não é o parâmetro");
        let juizo = juizo_boot(cmd);
        assert!(juizo.iter().all(|l| l.contains("PRESENTE")));
        let juizo = juizo_boot("quiet splash");
        assert!(juizo.iter().all(|l| l.contains("AUSENTE")));
    }
}

// ── 2.0 Fase 2 — A COLETA PELO FIO (o bus vivo é a fonte da verdade) ─────

/// O snapshot de boas-vindas: conecta, pede, colhe (None honesto quando
/// o bus não responde — o papel NOMEIA a ausência, nunca inventa).
pub fn colhe_do_bus(caminho: &std::path::Path) -> Option<BusColheita> {
    let (cli, rx) = elite_core::bus::BusClient::connect(caminho, "craft-dump")?;
    let _ = cli.send_req(elite_core::BusReq::Snapshot);
    // as boas-vindas + o snapshot chegam em sequência; o teto de 2s é o
    // juízo (o daemon vivo responde em ms; morto não responde nunca)
    let prazo = std::time::Duration::from_secs(2);
    let mut colheita = BusColheita::default();
    let inicio = std::time::Instant::now();
    while inicio.elapsed() < prazo {
        match rx.recv_timeout(std::time::Duration::from_millis(200)) {
            Ok(elite_core::BusMsg::Windows { windows }) => {
                colheita.janelas = windows.len() as u32;
                colheita.titulo = windows
                    .iter()
                    .find(|w| w.focused)
                    .and_then(|w| w.title.clone());
            }
            Ok(elite_core::BusMsg::Workspace(ws)) => {
                colheita.mesa = Some(ws);
            }
            Ok(elite_core::BusMsg::Media(m)) => {
                colheita.midia = Some(m);
            }
            Ok(elite_core::BusMsg::GameMode(g)) => {
                colheita.jogo = Some(g);
            }
            Ok(elite_core::BusMsg::Audio(a)) => {
                colheita.audio = Some(a);
            }
            Ok(elite_core::BusMsg::Ack { .. }) => {
                // o eco do Snapshot: a colheita já nasceu (as boas-vindas
                // precedem) — fecha o papel
                return Some(colheita);
            }
            Ok(_) => {}
            Err(_) => return Some(colheita),
        }
    }
    Some(colheita)
}

/// o que o bus entregou (a cara do estado vivo da sessão).
#[derive(Debug, Default, Clone)]
pub struct BusColheita {
    pub janelas: u32,
    pub titulo: Option<String>,
    pub mesa: Option<elite_core::WorkspaceInfo>,
    pub midia: Option<elite_core::MediaState>,
    pub jogo: Option<elite_core::GameModeState>,
    pub audio: Option<elite_core::AudioState>,
}

/// O PAPEL do bus (as linhas pt_BR do bloco "sessão viva").
pub fn linhas_bus(c: &BusColheita) -> Vec<String> {
    let mut out = Vec::new();
    out.push(format!("bus: {} janela(s) na sessão", c.janelas));
    match &c.titulo {
        Some(t) => out.push(format!("bus: janela focada — {t}")),
        None => out.push("bus: nenhuma janela focada (desktop puro)".into()),
    }
    if let Some(ws) = &c.mesa {
        out.push(format!(
            "bus: mesa {}/{}{}",
            ws.current,
            ws.count,
            ws.label.as_deref().map(|l| format!(" ({l})")).unwrap_or_default()
        ));
    }
    match &c.midia {
        Some(m) if m.player.is_some() => out.push(format!(
            "bus: mídia {} — {}{}",
            if m.playing { "tocando" } else { "pausada" },
            m.title.as_deref().unwrap_or("?"),
            m.artist.as_deref().map(|a| format!(" — {a}")).unwrap_or_default()
        )),
        Some(_) => out.push("bus: sem mídia (nenhum player MPRIS no ar)".into()),
        None => out.push("bus: mídia — SEM ESTADO no fio (o daemon fala?)".into()),
    }
    match &c.jogo {
        Some(g) if g.active => out.push(format!(
            "bus: modo de jogo ATIVO{} — GPU {}",
            g.game.as_deref().map(|j| format!(" ({j})")).unwrap_or_default(),
            if g.gpu_performance { "perfil 3D_FULL_SCREEN" } else { "sem perfil" }
        )),
        Some(_) => out.push("bus: modo de jogo inativo".into()),
        None => out.push("bus: modo de jogo — SEM ESTADO no fio".into()),
    }
    if let Some(a) = &c.audio {
        out.push(format!(
            "bus: áudio — saída {} ({}{})",
            a.sink_name.as_deref().unwrap_or("?"),
            a.sink_volume,
            if a.analog_preferred { " · analógica prioritária" } else { "" }
        ));
    }
    out
}

/// O PARSER do pactl info (a linha "Default Sink:" — o juízo puro).
pub fn pactl_default_sink(texto: &str) -> Option<String> {
    texto
        .lines()
        .find(|l| l.trim_start().starts_with("Default Sink:"))
        .map(|l| l.split_once(':').map(|(_, v)| v.trim().to_string()).unwrap_or_default())
        .filter(|s| !s.is_empty())
}

#[cfg(test)]
mod tests_fase2 {
    use super::*;
    use elite_core::bus::{BusServer, Incoming};
    use elite_core::{BusMsg, WindowInfo};

    #[test]
    fn o_legado_da_fase_2_e_completo() {
        for l in ["craft-menu", "craft-player", "craft-drawer", "craft-power", "craft-audio-route", "craft-toplevel", "swayidle"] {
            assert!(e_legado(l), "{l} é legado da 2.0");
        }
        // a família nova NÃO é legado
        for viva in ["craft-pick", "craft-update", "elite-dose", "nwg-drawer", "hyprlock"] {
            assert!(!e_legado(viva), "{viva} é a casa viva");
        }
    }

    #[test]
    fn a_colheita_do_bus_contra_o_daemon_falso() {
        let dir = std::env::temp_dir().join(format!("dump-bus-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let sock = dir.join("bus.sock");
        let (srv, rx) = BusServer::start(&sock).unwrap();
        // o daemon de mentira: boas-vindas completas + Ack
        std::thread::spawn(move || {
            for msg in rx {
                match msg {
                    Incoming::Hello { id, who } => {
                        assert!(who.starts_with("craft"));
                        srv.send_to(id, &BusMsg::Windows {
                            windows: vec![
                                WindowInfo { id: 1, app_id: "foot".into(), title: Some("foot".into()), focused: false, minimized: false, fullscreen: false },
                                WindowInfo { id: 2, app_id: "brave-browser".into(), title: Some("Arch Wiki".into()), focused: true, minimized: false, fullscreen: false },
                            ],
                        });
                        srv.send_to(id, &BusMsg::Workspace(elite_core::WorkspaceInfo {
                            current: 2, count: 4, label: None,
                        }));
                        srv.send_to(id, &BusMsg::Media(elite_core::MediaState {
                            player: Some("org.mpris.MediaPlayer2.mpv".into()),
                            title: Some("Stardew OST".into()),
                            artist: None,
                            playing: true,
                        }));
                        srv.send_to(id, &BusMsg::GameMode(elite_core::GameModeState {
                            active: true, game: Some("steam_app_413150".into()), gpu_performance: true,
                        }));
                        srv.send_to(id, &BusMsg::Audio(elite_core::AudioState {
                            sink_volume: 40, sink_muted: false, source_muted: false,
                            sink_name: Some("Starship/Matisse".into()), analog_preferred: true,
                        }));
                    }
                    Incoming::Req { cliente, req_id, .. } => {
                        srv.send_to(cliente, &BusMsg::Ack { id: req_id, ok: true });
                    }
                }
            }
        });
        let c = colhe_do_bus(&sock).expect("o bus falso responde");
        assert_eq!(c.janelas, 2);
        assert_eq!(c.titulo.as_deref(), Some("Arch Wiki"));
        assert_eq!(c.mesa.as_ref().unwrap().current, 2);
        assert!(c.midia.as_ref().unwrap().playing);
        assert!(c.jogo.as_ref().unwrap().active);
        assert_eq!(c.audio.as_ref().unwrap().sink_volume, 40);
        // o papel fala tudo em pt_BR
        let papel = linhas_bus(&c);
        let tudo = papel.join("\n");
        assert!(tudo.contains("2 janela(s)"));
        assert!(tudo.contains("mesa 2/4"));
        assert!(tudo.contains("tocando"));
        assert!(tudo.contains("3D_FULL_SCREEN"));
        assert!(tudo.contains("Starship/Matisse"));
        // bus morto: None honesto (o papel nomeia, nunca inventa)
        assert!(colhe_do_bus(&dir.join("nao-existe.sock")).is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn o_papel_do_bus_vazio_e_honrado() {
        let c = BusColheita::default();
        let papel = linhas_bus(&c);
        assert!(papel[0].contains("0 janela(s)"));
        assert!(papel[1].contains("desktop puro"));
        assert!(papel.join("\n").contains("SEM ESTADO no fio"));
        assert!(papel.join("\n").contains("SEM ESTADO no fio"));
    }

    #[test]
    fn o_default_sink_do_pactl_e_cacado_na_linha_certa() {
        let papel = "Server String: /run/user/1000/pulse/native\nLibrary Protocol Version: 35\nDefault Sink: alsa_output.pci-0000_14_0.analog-stereo\nDefault Source: alsa_input.pci-0000_14_0.analog-stereo\n";
        assert_eq!(
            pactl_default_sink(papel).as_deref(),
            Some("alsa_output.pci-0000_14_0.analog-stereo")
        );
        assert!(pactl_default_sink("sem nada").is_none());
    }
}
