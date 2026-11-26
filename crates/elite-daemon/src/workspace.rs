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
use std::sync::atomic::{AtomicU64, Ordering};
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

/// 1.0-100 — A MESA APRENDIDA DE UMA JANELA (o rastreamento que o bus
/// publica: `WindowInfo.desk`). None = a janela nunca foi focada sob
/// o olhar da casa — o consumidor presume visível (o desconhecido não
/// mentiu; a dock NUNCA apaga botão por falta de informação).
pub fn mesa_da_janela(janela: u32) -> Option<u32> {
    MESA.lock()
        .unwrap()
        .as_ref()
        .and_then(|m| m.por_janela.get(&janela).copied())
}

/// o instante do ÚLTIMO SET/STEP do sync (ms do boot da casa — o
/// aprendizado OBEDECE ao sync na janela curta: a tag velha da janela
/// movida entre mesas não arrasta a corrente para trás).
static SYNC_EM: AtomicU64 = AtomicU64::new(0);

fn agora_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn sync_fresco() -> bool {
    let t = SYNC_EM.load(Ordering::Relaxed);
    t != 0 && agora_ms().saturating_sub(t) < 1500
}

/// o APRENDIZADO: a janela focada crava a mesa dela (chamado pelo
/// wayland.rs quando o foco muda).
/// 1.0-100 — A JANELA DO SYNC MANDA: dentro de 1,5s de um set/step do
/// rc.xml, o foco que chega é a prova da mesa NOVA — a janela ganha a
/// tag da mesa corrente (a tag velha dela morre; o arrasto para trás
/// que a tag movida criaria morre com ela). Fora da janela do sync, a
/// regra de sempre: tag conhecida ≠ corrente arrasta a corrente (o
/// cinto dos binds `<default/>` do labwc que a casa não vê).
pub fn aprende(janela: u32) {
    let mut guard = MESA.lock().unwrap();
    let mesa = guard.get_or_insert_with(|| Mesa { atual: 1, por_janela: HashMap::new() });
    if sync_fresco() {
        // o sync é a autoridade: a janela focada MORA na mesa corrente
        mesa.por_janela.insert(janela, mesa.atual);
        return;
    }
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

/// 1.0-100 — O SYNC ABSOLUTO (o BusReq::DeskSet; o CLI `elite-daemon
/// desk N` do rc.xml): o labwc JÁ fez a troca (o Execute do bind corre
/// junto do GoToDesktop) — a casa registra a mesa, marca o instante do
/// sync e publica. NUNCA sintetiza tecla (o loop W-<n> fechava aqui).
/// Fora da faixa = recusa honesta (a tag da casa não mente).
pub fn define(n: u32) -> bool {
    let total_mesas = total();
    if n < 1 || n > total_mesas {
        return false;
    }
    SYNC_EM.store(agora_ms(), Ordering::Relaxed);
    {
        let mut guard = MESA.lock().unwrap();
        let mesa = guard.get_or_insert_with(|| Mesa { atual: 1, por_janela: HashMap::new() });
        mesa.atual = n;
    }
    publica();
    true
}

/// 1.0-100 — AS MESAS OCUPADAS CONHECIDAS (as mesas onde janelas
/// APRENDIDAS moram, excluindo a corrente — a base do passo `-occupied`).
fn ocupadas_excluindo(atual: u32) -> Vec<u32> {
    let guard = MESA.lock().unwrap();
    let Some(mesa) = guard.as_ref() else { return Vec::new() };
    let mut ms: Vec<u32> = mesa
        .por_janela
        .values()
        .copied()
        .filter(|&m| m >= 1 && m != atual)
        .collect();
    ms.sort_unstable();
    ms.dedup();
    ms
}

/// o PASSO com wrap no eixo 1D (left/right a partir da corrente).
fn passo_wrap(atual: u32, total: u32, esquerda: bool) -> u32 {
    if esquerda {
        if atual <= 1 { total } else { atual - 1 }
    } else if atual >= total {
        1
    } else {
        atual + 1
    }
}

/// 1.0-100 — O SYNC RELATIVO (o BusReq::DeskStep; os binds left/right e
/// os `-occupied` do rc.xml): quem sabe a mesa corrente é A CASA — o
/// cálculo com wrap mora aqui e a ocupação aprendida decide o
/// `-occupied` (a mesa anterior/seguinte que tem janela marcada; sem
/// nenhuma marcada, o passo simples honesto).
pub fn passo(dir: &str) -> bool {
    let total_mesas = total();
    let cur = atual();
    let alvo = match dir {
        "left" => passo_wrap(cur, total_mesas, true),
        "right" => passo_wrap(cur, total_mesas, false),
        "left-occupied" | "right-occupied" => {
            let esquerda = dir == "left-occupied";
            let ocupadas = ocupadas_excluindo(cur);
            let caída = if esquerda {
                // a maior mesa ocupada ANTES da corrente (wrap: a maior
                // de todas quando não há nenhuma antes)
                ocupadas.iter().rev().find(|&&m| m < cur).copied()
            } else {
                // a menor mesa ocupada DEPOIS da corrente (wrap: a
                // menor de todas quando não há nenhuma depois)
                ocupadas.iter().find(|&&m| m > cur).copied()
            };
            caída.unwrap_or_else(|| passo_wrap(cur, total_mesas, esquerda))
        }
        _ => return false, // direção desconhecida = recusa honesta
    };
    define(alvo)
}

/// O PULO (a barra pede, a casa sintetiza o bind W-<n>): o wlrctl
/// aperta Super+N no teclado VIRTUAL do labwc — o compositor faz o
/// resto (a mesma porta que o teclado do dono usa). Um fork por
/// clique (raro por desenho — a lei dos eventos).
/// 1.0-100 — O PULO TAMBÉM MARCA O SYNC (o foco que chega é prova da
/// mesa nova — a mesma janela de obediência do set/step do rc.xml).
pub fn pula(n: u32) -> bool {
    let total_mesas = total();
    if n < 1 || n > total_mesas {
        return false;
    }
    // marca o instante do pulo (o wayland.rs aprende com o foco que vem)
    crate::wayland::marca_pulo();
    // 1.0-100 — o pulo também marca o SYNC (a janela de obediência do
    // aprendizado: o foco que chega é prova da mesa nova, não arrasto
    // da tag velha)
    SYNC_EM.store(agora_ms(), Ordering::Relaxed);
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

    // ── 1.0-100 — O SYNC DA MESA (o rastreamento e o passo) ─────────

    /// helper do teste: planta o estado da mesa direto (as funções de
    /// sync operam sobre o MESA global — o teste planta, o veredito
    /// julga, o estado morre com o processo de teste).
    /// A TRAVA: os testes do estado correm em PARALELO no mesmo
    /// processo e o MESA é um global — sem ela, o planta de um teste
    /// pisoteia o veredito do outro (a corrida que nomeou os 2 falsos
    /// vermelhos da 1ª rodada). Cada teste de estado segura a trava
    /// pelo BLOCO INTEIRO (planta + gesto + juízo).
    static TRAVA_TESTE: Mutex<()> = Mutex::new(());

    fn planta(atual: u32, por_janela: &[(u32, u32)]) {
        let mut guard = MESA.lock().unwrap();
        *guard = Some(Mesa {
            atual,
            por_janela: por_janela.iter().copied().collect(),
        });
    }

    #[test]
    fn o_passo_wrap_anda_no_eixo_1d() {
        // o eixo da casa é 1D (4 mesas em fila): left da 1 com wrap na 4,
        // right da 4 com wrap na 1 — o MESMO wrap que o rc.xml manda
        assert_eq!(passo_wrap(1, 4, true), 4);
        assert_eq!(passo_wrap(2, 4, true), 1);
        assert_eq!(passo_wrap(3, 4, false), 4);
        assert_eq!(passo_wrap(4, 4, false), 1);
    }

    #[test]
    fn a_mesa_da_janela_e_a_tag_aprendida_ou_none() {
        let _t = TRAVA_TESTE.lock().unwrap();
        planta(2, &[(7, 1), (9, 3)]);
        assert_eq!(mesa_da_janela(7), Some(1));
        assert_eq!(mesa_da_janela(9), Some(3));
        assert_eq!(mesa_da_janela(5), None, "desconhecida = None honesto");
    }

    #[test]
    fn o_define_fora_da_faixa_recusa_honesto() {
        let _t = TRAVA_TESTE.lock().unwrap();
        planta(1, &[]);
        assert!(!define(0), "mesa 0 não existe");
        assert!(!define(9), "mesa 9 não existe na fábrica de 4");
    }

    #[test]
    fn o_passo_occupied_escolhe_a_mesa_com_janela_marcada() {
        let _t = TRAVA_TESTE.lock().unwrap();
        // corrente = 3; janelas marcadas nas mesas 1 e 4: o left-occupied
        // vai para a 1 (a maior ocupada ANTES), o right-occupied vai
        // para a 4 (a menor ocupada DEPOIS). O publica() sem bus na casa
        // é silêncio honesto — o ESTADO é o juízo aqui.
        planta(3, &[(10, 1), (11, 4)]);
        assert!(passo("left-occupied"));
        {
            let guard = MESA.lock().unwrap();
            let mesa = guard.as_ref().unwrap();
            assert_eq!(mesa.atual, 1, "left-occupied com ocupadas 1,4 e corrente 3 → mesa 1");
        }
        planta(3, &[(10, 1), (11, 4)]);
        assert!(passo("right-occupied"));
        {
            let guard = MESA.lock().unwrap();
            assert_eq!(guard.as_ref().unwrap().atual, 4, "right-occupied → mesa 4");
        }
    }

    #[test]
    fn o_passo_occupied_sem_ocupadas_cai_no_wrap_simples() {
        let _t = TRAVA_TESTE.lock().unwrap();
        planta(2, &[]);
        assert!(passo("left-occupied"));
        {
            let guard = MESA.lock().unwrap();
            assert_eq!(guard.as_ref().unwrap().atual, 1, "sem marcadas: o wrap simples manda");
        }
    }

    #[test]
    fn o_aprendizado_obedece_ao_sync_fresco() {
        let _t = TRAVA_TESTE.lock().unwrap();
        // com o SYNC fresco (define acabou de correr), a janela focada
        // ganha a tag da mesa corrente — a tag velha dela NÃO arrasta
        planta(2, &[(42, 1)]);
        assert!(define(4));
        aprende(42);
        {
            let guard = MESA.lock().unwrap();
            let mesa = guard.as_ref().unwrap();
            assert_eq!(mesa.atual, 4, "o sync não é desfeito pela tag velha");
            assert_eq!(
                mesa.por_janela.get(&42),
                Some(&4),
                "a janela movida ganha a tag da mesa nova"
            );
        }
    }
}
