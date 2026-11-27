// ═════════════════════════════════════════════════════════════════════════
// elite-core · rede — A LEI DA REDE DA CASA NA FUNDAÇÃO (1.0-109)
// ─────────────────────────────────────────────────────────────────────────
// A EVIDÊNCIA REAL DO DUMP 1.0-108: o clique ESQUERDO no ícone de Rede
// da top bar não executava ação nenhuma e o `nm-connection-editor`
// exige CRIAR perfis manualmente em vez de LISTAR as redes Wi-Fi
// próximas com 1 clique como o Bluetooth (a paridade que o dono
// pediu). A diretriz da dose: o `craft-net` (o seletor de 1 clique)
// nasce na família craft-tools e a LEI DA CONEXÃO PRINCIPAL (E163: a
// ethernet vence, o par `(DEVICE, CONNECTION)` vive no last-net.state,
// a queda é `nmcli device disconnect` — NUNCA `ip link set down` — e a
// volta é `ip link set up` + `managed yes` + `connection up` /
// `device connect`) desce da bar para A FUNDAÇÃO — uma lei só, duas
// superfícies (o direito da top bar e o toggle do seletor vestem o
// MESMO julgamento).
//
// A GRAMÁTIA DO nmcli -t (terse): campos separados por `:` com o `\:`
// como escape — o SSID com dois-pontos sobrevive (`split_nmcli_t`).
// Tudo PURO onde dá (os juízos testam sem rede); os verbos nmcli são
// best-effort com o silêncio honesto de sempre.
// ═════════════════════════════════════════════════════════════════════════

use std::path::PathBuf;
use std::process::{Command, Stdio};

/// A divisão de UMA linha do `nmcli -t` (o `\:` é o escape do
/// dois-pontos — o SSID "Vivo:Fibra" é um campo só).
pub fn split_nmcli_t(linha: &str) -> Vec<String> {
    let mut campos = Vec::new();
    let mut atual = String::new();
    let mut escapado = false;
    for c in linha.chars() {
        if escapado {
            atual.push(c);
            escapado = false;
            continue;
        }
        match c {
            '\\' => escapado = true,
            ':' => {
                campos.push(atual.clone());
                atual.clear();
            }
            _ => atual.push(c),
        }
    }
    campos.push(atual);
    campos
}

/// A CONEXÃO PRINCIPAL do `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION
/// device status`: a ETHERNET conectada vence (a lei da dose: cabo é o
/// caminho de menor dúvida), senão a Wi-Fi conectada. Devolve
/// (dispositivo, conexão) — None quando nenhuma rede viva mora no
/// papel (nada a derrubar: o clique é RELIGAR).
pub fn conexao_principal(saida: &str) -> Option<(String, String)> {
    let mut wifi: Option<(String, String)> = None;
    for linha in saida.lines() {
        let c = split_nmcli_t(linha);
        if c.len() < 3 {
            continue;
        }
        let (dev, tipo, estado) = (c[0].as_str(), c[1].as_str(), c[2].as_str());
        if dev == "lo" || tipo == "loopback" {
            continue;
        }
        if estado != "connected" {
            continue;
        }
        let con = c.get(3).cloned().unwrap_or_default();
        if tipo == "ethernet" {
            // a ETHERNET vence na hora (a lei: cabo > sem fio)
            return Some((dev.to_string(), con));
        }
        if tipo == "wifi" && wifi.is_none() {
            wifi = Some((dev.to_string(), con));
        }
    }
    wifi
}

/// O CONTEÚDO do last-net.state (o par que volta a viver no clique
/// seguinte — "DEVICE=…" / "CONNECTION=…" em linhas próprias).
pub fn conteudo_last_net(dev: &str, con: &str) -> String {
    format!("DEVICE={dev}\nCONNECTION={con}\n")
}

/// A LEITURA do last-net.state: o par (DEVICE, CONNECTION) guardado no
/// clique de derrubar — None quando o papel está vazio/torto (a
/// detecção viva assume).
pub fn le_last_net(conteudo: &str) -> Option<(String, String)> {
    let mut dev = None;
    let mut con = None;
    for linha in conteudo.lines() {
        // o valor VAZIO é ausência, não dispositivo (o papel torto de era
        // devolvia "" e o religar nascia com um fantasma sem nome)
        if let Some(v) = linha.strip_prefix("DEVICE=") {
            if !v.trim().is_empty() {
                dev = Some(v.trim().to_string());
            }
        } else if let Some(v) = linha.strip_prefix("CONNECTION=") {
            if !v.trim().is_empty() {
                con = Some(v.trim().to_string());
            }
        }
    }
    Some((dev?, con.unwrap_or_default()))
}

/// O DISPOSITIVO PARA RELIGAR (a detecção viva quando o papel cala):
/// o DEVICE do last-net.state que AINDA mora no status ganha; senão a
/// primeira ETHERNET com CABO (state != unavailable — sem cabo não há
/// religação de cabo); senão a primeira placa Wi-Fi. None = nada a
/// religar no hardware (o clique é honesto: sem placa, sem gesto).
pub fn dev_para_religar(saida: &str, last: Option<(String, String)>) -> Option<String> {
    let devs: Vec<Vec<String>> = saida
        .lines()
        .map(split_nmcli_t)
        .filter(|c| c.len() >= 3 && c[0] != "lo" && c[1] != "loopback")
        .collect();
    // 1. o last-net que ainda vive no papel do hardware
    if let Some((dev, _con)) = last {
        if devs.iter().any(|c| c[0] == dev) {
            return Some(dev);
        }
    }
    // 2. a ETHERNET com cabo (unavailable = SEM cabo — não é religação)
    if let Some(c) = devs.iter().find(|c| c[1] == "ethernet" && c[2] != "unavailable") {
        return Some(c[0].clone());
    }
    // 3. a primeira placa Wi-Fi
    devs.iter().find(|c| c[1] == "wifi").map(|c| c[0].clone())
}

/// UMA REDE Wi-Fi ao alcance (a lista do craft-net — o SECURITY veste
/// o cadeado e o juízo da senha: protegida SEM perfil salvo pede a
/// senha em diálogo limpo, o resto conecta com 1 clique).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct RedeWifi {
    pub em_uso: bool,
    pub ssid: String,
    pub sinal: u8,
    pub seguranca: String,
}

/// A LISTA das redes Wi-Fi do `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY
/// device wifi list` (com `--rescan auto` na chamada de quem pergunta):
/// as linhas com SSID vazio (o hidden de fábrica) não são escolha.
pub fn redes_wifi(saida: &str) -> Vec<RedeWifi> {
    let mut redes = Vec::new();
    for linha in saida.lines() {
        let c = split_nmcli_t(linha);
        if c.len() < 2 || c[1].trim().is_empty() {
            continue; // linha de cabeçalho ou SSID oculto
        }
        let sinal = c
            .get(2)
            .and_then(|s| s.trim().parse::<u8>().ok())
            .unwrap_or(0);
        redes.push(RedeWifi {
            em_uso: c[0].trim() == "*",
            ssid: c[1].clone(),
            sinal,
            seguranca: c.get(3).cloned().unwrap_or_default(),
        });
    }
    redes
}

// ── os VERBOS (best-effort: o nmcli decide no rig; a voz é do papel) ────

/// A FOTO do `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status`
/// (None honesto quando o nmcli não mora na máquina — a voz é do
/// chamador).
pub fn nmcli_status() -> Option<String> {
    let out = Command::new("nmcli")
        .args(["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"])
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// O CAMINHO do last-net.state (o tmpfs da sessão — o par que volta a
/// viver no clique seguinte; o mesmo endereço da diretriz do dono).
pub fn last_net_path() -> PathBuf {
    let dir = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"));
    dir.join("elite/last-net.state")
}

/// O RELIGAR DA CONEXÃO PRINCIPAL (o caminho da ordem do dono, palavra
/// por palavra): o par do last-net.state (ou a ETHERNET com cabo, senão
/// a Wi-Fi — `dev_para_religar` julga no papel vivo) volta com o link
/// DE PÉ (`ip link set up`, best-effort — o polkit do rig decide), o
/// dispositivo DEVOLVIDO ao NetworkManager (`managed yes`) e a conexão
/// SALVA em cena (`nmcli connection up`) com a queda honesta para o
/// `nmcli device connect` quando o papel não casa mais.
pub fn religa_conexao_principal(foto: &str) {
    let last = std::fs::read_to_string(last_net_path())
        .ok()
        .and_then(|t| le_last_net(&t));
    let Some(dev) = dev_para_religar(foto, last.clone()) else {
        return; // nada a religar no hardware (honesto, sem gesto fantasma)
    };
    // o link DE PÉ (best-effort: sem root o nmcli abaixo ainda levanta)
    let _ = Command::new("ip")
        .args(["link", "set", &dev, "up"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    // o dispositivo VOLTA ao NetworkManager (o "não disponível" de era
    // morre: o manager é o dono do link)
    let _ = Command::new("nmcli")
        .args(["device", "set", &dev, "managed", "yes"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    // a conexão SALVA primeiro; sem papel casa, o device cru
    if let Some((_, con)) = last {
        if !con.is_empty() {
            let ok = Command::new("nmcli")
                .args(["connection", "up"])
                .arg(&con)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if ok {
                return;
            }
        }
    }
    let _ = Command::new("nmcli")
        .args(["device", "connect"])
        .arg(&dev)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// O DERRUBAR/RELIGAR DA CONEXÃO PRINCIPAL (a ethernet vence — a lei da
/// dose): a principal VIVA cai com o par GUARDADO no last-net.state e o
/// `nmcli device disconnect` (NUNCA `ip link set down` — o link do driver
/// não é do dono); SEM principal viva o mesmo clique RELIGA (o toggle de
/// 1 clique que o dono pediu — o estado de era "não disponível" sem
/// volta morre por desenho).
pub fn alterna_conexao_principal() {
    let Some(foto) = nmcli_status() else {
        return; // nmcli calado: nada a julgar (o silêncio é honesto)
    };
    match conexao_principal(&foto) {
        Some((dev, con)) => {
            // o par fica no papel ANTES da queda (o clique seguinte tem
            // a quem chamar de volta mesmo com o status mudado)
            let caminho = last_net_path();
            if let Some(pai) = caminho.parent() {
                let _ = std::fs::create_dir_all(pai);
            }
            let _ = std::fs::write(&caminho, conteudo_last_net(&dev, &con));
            let _ = Command::new("nmcli")
                .args(["device", "disconnect"])
                .arg(&dev)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
        None => religa_conexao_principal(&foto),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn e109_a_ethernet_viva_e_a_principal() {
        let foto = "lo:loopback:connected (externally):\n\
                    enp7s0:ethernet:connected:Cabo de casa\n\
                    wlp3s0:wifi:disconnected:\n";
        assert_eq!(
            conexao_principal(foto),
            Some(("enp7s0".to_string(), "Cabo de casa".to_string()))
        );
        // SEM cabo: o wifi conectado é a principal
        let sem_cabo = "enp7s0:ethernet:unavailable:\nwlp3s0:wifi:connected:MinhaRede\n";
        assert_eq!(
            conexao_principal(sem_cabo),
            Some(("wlp3s0".to_string(), "MinhaRede".to_string()))
        );
        assert_eq!(conexao_principal("enp7s0:ethernet:disconnected:\n"), None);
    }

    #[test]
    fn e109_o_last_net_guarda_e_devolve_o_par() {
        let papel = conteudo_last_net("enp7s0", "Cabo de casa");
        assert_eq!(
            le_last_net(&papel),
            Some(("enp7s0".to_string(), "Cabo de casa".to_string()))
        );
        assert_eq!(le_last_net(""), None);
        assert_eq!(le_last_net("DEVICE=\n"), None);
        assert_eq!(
            le_last_net("DEVICE=wlp3s0\n"),
            Some(("wlp3s0".to_string(), "".to_string()))
        );
    }

    #[test]
    fn e109_a_deteccao_viva_para_religar() {
        let foto = "lo:loopback:connected::\nenp7s0:ethernet:disconnected:\nwlp3s0:wifi:disconnected:\n";
        // o last-net que AINDA vive no papel do hardware vence
        assert_eq!(
            dev_para_religar(foto, Some(("enp7s0".to_string(), "Cabo".to_string()))),
            Some("enp7s0".to_string())
        );
        // o last-net de um device QUE NÃO EXISTE mais cai para a detecção
        assert_eq!(
            dev_para_religar(foto, Some(("eth9".to_string(), "x".to_string()))),
            Some("enp7s0".to_string())
        );
        assert_eq!(dev_para_religar(foto, None), Some("enp7s0".to_string()));
        // SEM cabo: a primeira placa Wi-Fi
        let sem_cabo = "enp7s0:ethernet:unavailable:\nwlp3s0:wifi:disconnected:\n";
        assert_eq!(dev_para_religar(sem_cabo, None), Some("wlp3s0".to_string()));
        assert_eq!(dev_para_religar("lo:loopback:connected::\n", None), None);
    }

    #[test]
    fn e109_a_lista_das_redes_wifi_com_sinal_e_cadeado() {
        // a gramática do `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY` (o
        // --rescan auto é da chamada): o SSID com dois-pontos sobrevive
        // (o \: é o escape), a conectada marca o IN-USE e a SECURANÇA
        // vira o cadeado do seletor
        let saida = "*:Vivo\\:Fibra:82:WPA2\n  :CasaAberta:45:\n  :--:10:WPA3\n";
        let redes = redes_wifi(saida);
        assert_eq!(redes.len(), 3, "3 redes vivas: {redes:?}");
        assert_eq!(
            redes[0],
            RedeWifi {
                em_uso: true,
                ssid: "Vivo:Fibra".to_string(),
                sinal: 82,
                seguranca: "WPA2".to_string()
            }
        );
        assert!(!redes[1].em_uso);
        assert_eq!(redes[1].seguranca, ""); // rede ABERTA: 1 clique direto
        assert_eq!(redes[2].ssid, "--"); // o SSID de traços é nome legítimo
        // o SSID VAZIO (hidden de fábrica) não é escolha
        assert!(redes_wifi("*::77:WPA2\n").is_empty());
    }
}
