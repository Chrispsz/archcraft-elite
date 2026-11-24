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
    "craft-audio",      // a UI Python (o roteador craft-audio-route é OUTRO papel)
    "craft-bars",       // o supervisor sh — o lançador único é elite-daemon session
    "craft-connect",    // os menus fuzzel de rede/bluetooth — iwgtk/blueman são a tela
    "craft-pin-pick",   // o picker fuzzel de pins — o popover da dock tomou o lugar
    "craft-menu",       // o painel fuzzel — Fase 2 rebobina os últimos chamadores
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
        // o roteador de áudio NÃO é o craft-audio aposentado
        assert!(!e_legado("craft-audio-route"), "o roteador é tuning vivo");
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
