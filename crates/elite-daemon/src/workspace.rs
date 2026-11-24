// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — workspace.rs (2.0 Fase 2) — A MESA DO LABWC
// ═════════════════════════════════════════════════════════════════════════
// A HONESTIDADE PRIMEIRO: o labwc NÃO expõe protocolo de mesas (o
// ext-workspace não existe nele; o cosmic-workspace foi aposentado
// upstream). O que a casa TEM de verdade:
//   · os NOMES das mesas no rc.xml (<desktops><names>) — o total e os
//     rótulos vêm daí (parse puro, testado);
//   · os BINDS W-<n> do rc.xml — a porta de ENTRADA por teclado;
//   · o zwp-virtual-keyboard do labwc (via wlrctl — a casa já vende o
//     binário): o daemon SINTETIZA o bind W-<n> quando a barra pede o
//     pulo (um fork por clique — raro por desenho);
//   · o APRENDIZADO: o pulo sintetizado muda o foco; a janela focada
//     DEPOIS do pulo fica TAGGEADA com a mesa — o foco futuro dela
//     re-crava a mesa corrente (a heurística cobre o teclado do dono
//     SEM protocolo: W-3 foca uma janela que já morou na mesa 3).
// O current publicado no bus é sempre a MELHOR HIPÓTESE da casa — e o
// papel do código e do inventário dizem exatamente isto.
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use elite_core::BusMsg;


/// o estado da mesa (current + o mapa de aprendizado por janela).
struct Mesa {
    atual: u32,
    por_janela: HashMap<u32, u32>,
}

static MESA: Mutex<Option<Mesa>> = Mutex::new(None);

/// rc.xml VIVO da sessão (XDG_CONFIG_HOME labwc; o padrão da casa).
fn rc_xml_path() -> PathBuf {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/root".into())).join(".config")
        });
    base.join("labwc/rc.xml")
}

/// os NOMES das mesas do rc.xml (o parse puro da casa: <desktops><names>
/// <name> — o total é o len; o default honesto é a fábrica "1".."4").
pub fn nomes_do_rc(texto: &str) -> Vec<String> {
    let mut nomes = Vec::new();
    if let Some(pos_desktops) = texto.find("<desktops>") {
        let fim = texto[pos_desktops..]
            .find("</desktops>")
            .map(|i| pos_desktops + i)
            .unwrap_or(texto.len());
        let corpo = &texto[pos_desktops..fim];
        if let Some(pos_names) = corpo.find("<names>") {
            let fim_names = corpo[pos_names..]
                .find("</names>")
                .map(|i| pos_names + i)
                .unwrap_or(corpo.len());
            let bloco = &corpo[pos_names..fim_names];
            // os pares <name>…</name> podem viver NA MESMA LINHA (o
            // editor do dono não é obrigado a quebrar linha) — o parse
            // anda de par em par, não de linha em linha
            let mut resto = bloco;
            while let Some(i) = resto.find("<name>") {
                resto = &resto[i + "<name>".len()..];
                if let Some(j) = resto.find("</name>") {
                    nomes.push(resto[..j].trim().to_string());
                    resto = &resto[j + "</name>".len()..];
                } else {
                    break;
                }
            }
        }
    }
    if nomes.is_empty() {
        nomes = ["1", "2", "3", "4"].iter().map(|s| s.to_string()).collect();
    }
    nomes
}

/// o TOTAL de mesas (o rc.xml vivo; fábrica 4).
pub fn total() -> u32 {
    std::fs::read_to_string(rc_xml_path())
        .map(|t| nomes_do_rc(&t).len() as u32)
        .unwrap_or(4)
        .max(1)
}

/// o NOME humano da mesa N (None quando fora da lista).
pub fn nome(n: u32) -> Option<String> {
    let nomes = std::fs::read_to_string(rc_xml_path())
        .map(|t| nomes_do_rc(&t))
        .unwrap_or_else(|_| nomes_do_rc(""));
    nomes.get((n.max(1) - 1) as usize).cloned()
}

/// a mesa CORRENTE (a melhor hipótese da casa — ver cabeçalho).
pub fn atual() -> u32 {
    MESA.lock().unwrap().as_ref().map(|m| m.atual).unwrap_or(1)
}

/// o APRENDIZADO: a janela focada crava a mesa dela (chamado pelo
/// wayland.rs quando o foco segue um pulo sintetizado).
pub fn aprende(janela: u32) {
    let mut guard = MESA.lock().unwrap();
    let mesa = guard.get_or_insert_with(|| Mesa { atual: 1, por_janela: HashMap::new() });
    if let Some(&m) = mesa.por_janela.get(&janela) {
        if m != mesa.atual {
            mesa.atual = m;
            drop(guard);
            publica();
        }
    } else {
        // primeira vez vista: mora na mesa corrente (a tag nasce)
        mesa.por_janela.insert(janela, mesa.atual);
    }
}

/// O PULO (a barra pede, a casa sintetiza o bind W-<n>): o wlrctl
/// aperta Super+N no teclado VIRTUAL do labwc — o compositor faz o
/// resto (a mesma porta que o teclado do dono usa). Um fork por
/// clique (raro por desenho — a lei dos eventos).
pub fn pula(n: u32) -> bool {
    let total_mesas = total();
    if n < 1 || n > total_mesas {
        return false;
    }
    // marca o instante do pulo (o wayland.rs aprende com o foco que vem)
    crate::wayland::marca_pulo();
    // a mesa cravada AGORA (o foco que chega confirma; se nenhum vem,
    // a hipótese segue — o teclado do dono é a fonte final)
    {
        let mut guard = MESA.lock().unwrap();
        let mesa = guard.get_or_insert_with(|| Mesa { atual: 1, por_janela: HashMap::new() });
        mesa.atual = n;
    }
    publica();
    // wlrctl keyboard type <n> modifiers SUPER (a gramática provada do
    // binário da casa: 'type' 'texto' 'modifiers' 'SUPER')
    let n_str = n.to_string();
    let ok = std::process::Command::new("wlrctl")
        .args(["keyboard", "type", &n_str, "modifiers", "SUPER"])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    ok
}

fn publica() {
    crate::nucleo::pub_bus(&BusMsg::Workspace(elite_core::WorkspaceInfo {
        current: atual(),
        count: total(),
        label: nome(atual()),
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    const RC_CASA: &str = r#"
<labwc_config>
  <desktops>
    <popupTime>800</popupTime>
    <names>
      <name>1</name>
      <name>2</name>
      <name>3</name>
      <name>4</name>
    </names>
  </desktops>
</labwc_config>
"#;

    #[test]
    fn os_quatro_nomes_do_rc_da_casa() {
        assert_eq!(nomes_do_rc(RC_CASA), vec!["1", "2", "3", "4"]);
    }

    #[test]
    fn sem_desktops_e_a_fabrica_honesta() {
        assert_eq!(nomes_do_rc("<labwc_config></labwc_config>"), vec!["1", "2", "3", "4"]);
        assert_eq!(nomes_do_rc(""), vec!["1", "2", "3", "4"]);
    }

    #[test]
    fn nomes_humanos_do_dono_sao_respeitados() {
        let rc = r#"<labwc_config><desktops><names>
          <name>Código</name><name>Web</name>
        </names></desktops></labwc_config>"#;
        assert_eq!(nomes_do_rc(rc), vec!["Código", "Web"]);
    }

    #[test]
    fn o_total_e_o_nome_pela_ordem() {
        // (a leitura do disco mora nas funções; aqui o contrato do PARSE)
        let nomes = nomes_do_rc(RC_CASA);
        assert_eq!(nomes.len(), 4);
        // o índice 3 → a 4ª mesa (1-based na cara do dono)
        assert_eq!(nomes[3], "4");
    }
}
