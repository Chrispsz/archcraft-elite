// ELITE · craft-dock-rs — sock.rs (2.0 Fase 2). O CLIENTE DO BUS VIVO:
// o fio da dock é o /run/user/$UID/elite/bus.sock do elite-daemon (o
// toplevel.sock do craft-toplevel.c morreu com o binário de C). O
// protocolo no fio é o quadro da casa (4B LE + JSON da BusMsg) e a
// LÍNGUA é a do elite-core: Windows (a ORDEM é o anel MRU — o rank
// da dock nasce do índice), Req::Activate/Minimize/Close por id e o
// Ack que ecoa o pedido.
//
// O PORTO DA DOCK v2:
//   · a THREAD DE FUNDO da UI (ui.rs) assina o bus com o BusClient da
//     fundação (Hello + reconexão 5→20→100ms E135 embutida): cada
//     `Windows` publicado vira Snapshot no canal mpsc — o botão da
//     janela que FECHOU some NO MESMO frame (o evento chega da fonte);
//   · os VERBES do clique são clientes CURTOS (connect a unix socket
//     custa µs — a gramática da casa desde o C): Hello + Req + Ack,
//     morte em 1s — a LIST fresca no clique (a prova E135) e o verbo
//     confirmado são round-trips síncronos de verdade.
//
// As flags da casa seguem (1=maximized saiu na 2.0 réu E76 · 2=minimized
// · 4=activated · 8=fullscreen) e a GRAMÁTICA DE CASAMENTO é a mesma
// de sempre (a inteligência da dock não mudou de endereço).
// Tudo aqui é std-only e TESTADO contra um daemon FALSO que fala o
// protocolo do bus (o parsing é função pura).
use std::collections::HashMap;
use std::os::unix::net::UnixStream;
use std::path::Path;

/// Flags do protocolo (o mapa do daemon — ver cabeçalho).
/// (F_MAXIMIZED saiu na 2.0: réu E76 — nenhum leitor na árvore inteira,
/// nem na gui; o maximizado não muda o verbo da dock.)
pub const F_MINIMIZED: u32 = 2;
pub const F_ACTIVATED: u32 = 4;
#[cfg_attr(not(feature = "gui"), allow(dead_code))] // o leitor mora na ui.rs (gui)
pub const F_FULLSCREEN: u32 = 8;

/// Uma janela REAL da sessão (a entrada do snapshot).
#[derive(Debug, Clone, Default)]
pub struct WindowEntry {
    pub id: u64,
    pub flags: u32,
    pub rank: u32,
    pub app_id: String,
    pub title: String,
    /// 1.0-100 — a mesa APRENDIDA da janela (None = desconhecida — o
    /// dock presume visível; o .other-workspace só veste com mesa
    /// CONHECIDA ≠ a corrente: o botão nunca se esconde por falta de
    /// informação). O consumidor mora na ui.rs (feature gui — o núcleo
    /// sem gui carrega o atributo de cortesia da casa).
    #[cfg_attr(not(feature = "gui"), allow(dead_code))]
    pub desk: Option<u32>,
}

/// O snapshot LIST: janelas por id + a janela focada (0 = nenhuma).
#[derive(Debug, Clone, Default)]
pub struct Snapshot {
    pub windows: HashMap<u64, WindowEntry>,
    pub focused: u64,
}

/// Converte o `Windows` do bus em Snapshot da dock (puro — o teste
/// alimenta a lista da casa direto). A ORDEM é o anel MRU (índice 0 =
/// topo): o rank nasce da posição; a focada é a flag; o título vazio
/// do bus (None) vira string vazia (a gramática interna da dock).
pub fn de_bus_windows(windows: &[elite_core::WindowInfo]) -> Snapshot {
    let mut snap = Snapshot::default();
    for (rank, w) in windows.iter().enumerate() {
        let mut flags = 0u32;
        if w.minimized {
            flags |= F_MINIMIZED;
        }
        if w.focused {
            flags |= F_ACTIVATED;
            snap.focused = w.id as u64;
        }
        if w.fullscreen {
            flags |= F_FULLSCREEN;
        }
        snap.windows.insert(
            w.id as u64,
            WindowEntry {
                id: w.id as u64,
                flags,
                rank: rank as u32,
                app_id: w.app_id.clone(),
                title: w.title.clone().unwrap_or_default(),
                desk: w.desk,
            },
        );
    }
    snap
}

// ── a gramática de casamento da casa (v2.10.0→v2.10.6) ────────────────

/// v2.10 — as 3 formas canônicas de um candidato (original, minúscula,
/// título): o match do wlrctl era exato e case-sensitive ("Brave-
/// browser" nunca casava com "brave-browser"). Dedup na ordem.
/// (2.0 E143-corrige: a gramática só veste os TESTES de casamento —
/// a casa em produção casa pelo norm/resolve; cfg(test) com voz)
#[cfg(test)]
pub fn case_variants(c: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for v in [c.to_string(), c.to_lowercase(), title_case(c)] {
        if !v.is_empty() && !out.contains(&v) {
            out.push(v);
        }
    }
    out
}

/// E134 — A NORMALIZAÇÃO DO TRAVESSÃO da casa para o CASAMENTO de
/// janelas: minúsculas + '_' equivale a '-'. O caso cravado pelo dono
/// (dump 1.0-80): o pin `hydra_plus.desktop` (stem "hydra_plus") e o
/// app_id do compositor "hydra-plus" são O MESMO app — sem a norma, o
/// exato e o near falham nos DOIS sentidos e o app aberto nascia botão
/// RAW duplicado ao lado do pin. A norma é AQUI (camada de casamento)
/// e não no fold do icons.rs (a chave de ÍCONE segue a gramática dela).
pub fn norm(s: &str) -> String {
    s.to_lowercase().replace('_', "-")
}

/// O title() do Python (cada palavra capitalizada, resto minúsculo).
/// (idem E143-corrige: só veste os testes da gramática)
#[cfg(test)]
fn title_case(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut cap = true;
    for ch in s.chars() {
        if ch.is_alphanumeric() {
            if cap {
                out.extend(ch.to_uppercase());
                cap = false;
            } else {
                out.extend(ch.to_lowercase());
            }
        } else {
            out.push(ch);
            cap = true;
        }
    }
    out
}

/// v2.10.6 — contenção ≥4 chars COM FRONTEIRA: 'brave' ⊂ 'brave-
/// browser' casa (o '-' é fronteira), mas 'foot' ⊂ 'footclient' NÃO
/// (letra colada é outro app). Vale nos DOIS sentidos. A fronteira é
/// o caractere colado na ocorrência não ser letra/número.
pub fn near_match(a: &str, c: &str) -> bool {
    if a.chars().count() < 4 || c.chars().count() < 4 {
        return false;
    }
    for (x, y) in [(c, a), (a, c)] {
        // 1.0-103 — while let duplo (a clippy-lente da auditoria): os
        // dois breaks viram a condição do laço
        let mut from = 0usize;
        while let (Some(hay), Some(rel)) = (y.get(from..), y.get(from..).and_then(|h| h.find(x))) {
            let i = from + rel;
            let _ = hay; // a fatia do par (o juízo usa y direto abaixo)
            let before_ok = y[..i].chars().next_back().is_none_or(|ch| !ch.is_alphanumeric());
            let after_ok = y[i + x.len()..].chars().next().is_none_or(|ch| !ch.is_alphanumeric());
            if before_ok && after_ok {
                return true;
            }
            from = i + 1;
        }
    }
    false
}

/// O STEM de um app_id composto ("org.xfce.Thunar" → "thunar"; vazio
/// para id vazio).
pub fn stem_of(app_id: &str) -> &str {
    if app_id.is_empty() {
        ""
    } else {
        app_id.rsplit('.').next().unwrap_or("")
    }
}

/// v2.10.3→v2.10.6 — as janelas REAIS de um app no snapshot: app_id
/// casa os candidatos (case-insensitive: exato, STEM composto, ou
/// contenção com fronteira) OU o título contém o nome de exibição
/// (último recurso — SÓ quando strict=false; a lei E36: o verbo
/// DESTRUTIVO nunca casa por título). Devolve ids ORDENADOS.
pub fn windows_of_key(
    snap: &Snapshot,
    candidates: &[String],
    display_name: &str,
    strict: bool,
) -> Vec<u64> {
    // E134 — o casamento NASCE NORMALIZADO ('_' == '-'): hydra_plus
    // casa hydra-plus em TODAS as formas (exato, stem, near) — o
    // agrupamento de pin + aberto em UM só ícone é a ordem do dono.
    let cands: Vec<String> = candidates.iter().map(|c| norm(c)).collect();
    let name = norm(display_name.trim());
    let mut out = Vec::new();
    for w in snap.windows.values() {
        let a = norm(&w.app_id);
        let t = norm(&w.title);
        let stem = norm(stem_of(&a));
        let near = cands.iter().any(|c| near_match(&a, c));
        if cands.iter().any(|c| c == &a)
            || (!stem.is_empty() && cands.iter().any(|c| c == &stem))
            || near
            || (!strict && !name.is_empty() && t.contains(&name))
        {
            out.push(w.id);
        }
    }
    out.sort_unstable();
    out
}

/// As janelas do botão RAW (o _raw_windows do Python): app_id == chave
/// OU stem == chave OU contenção com fronteira; sem app_id, a chave
/// veio do título e casa no título (fora do strict — lei E36).
pub fn raw_windows(snap: &Snapshot, key: &str, strict: bool) -> Vec<u64> {
    // E134 — a norma do travessão ('_' == '-') vale TAMBÉM no raw: a
    // janela "hydra-plus" veste a chave "hydra_plus" que o comm cravou
    let k = norm(key);
    let mut out = Vec::new();
    for w in snap.windows.values() {
        let a = norm(&w.app_id);
        let t = norm(&w.title);
        let stem = norm(stem_of(&a));
        // o RAW é EXATO por desenho (a lei E130 do botão cru): o app_id
        // inteiro OU o stem — o near_match de subdomínio ('kolunmi'
        // dentro de 'io.github.kolunmi.bazaar') NÃO casa: o raw não
        // adivinha, só veste a chave que o comm cravou
        if (!a.is_empty() && (a == k || (stem == k && !stem.is_empty())))
            || (!strict && a.is_empty() && !k.is_empty() && t.contains(&k))
        {
            out.push(w.id);
        }
    }
    out.sort_unstable();
    out
}

/// v2.10.1 — a próxima janela DO APP (o anel por id): a última que
/// NÓS focamos, senão a focada de verdade, senão a mais recente (o
/// menor rank = topo do MRU do daemon — a semântica do alt-tab).
pub fn cycle_next(snap: &Snapshot, wids: &[u64], last_act: Option<u64>) -> Option<u64> {
    if wids.is_empty() {
        return None;
    }
    if let Some(last) = last_act {
        if let Some(i) = wids.iter().position(|w| *w == last) {
            return Some(wids[(i + 1) % wids.len()]);
        }
    }
    if let Some(w) = wids.iter().find(|w| {
        snap.windows
            .get(w)
            .map(|e| e.flags & F_ACTIVATED != 0)
            .unwrap_or(false)
    }) {
        return Some(*w);
    }
    wids.iter()
        .min_by_key(|w| snap.windows.get(w).map(|e| e.rank).unwrap_or(u32::MAX))
        .copied()
}

/// E88 — a chave do lançamento MAPEOU? (o guard só protege o vão entre
/// o clique e a janela; mapeou = o vão acabou). O stem do desktop-id
/// casa o app_id: exato OU contenção com fronteira (a mesma gramática).
pub fn key_mapped(snap: &Snapshot, key: &str) -> bool {
    // E134 — a norma do travessão aqui também (hydra_plus mapeia)
    let stem = norm(key.strip_suffix(".desktop").unwrap_or(key));
    if stem.is_empty() {
        return false;
    }
    for w in snap.windows.values() {
        let a = norm(&w.app_id);
        if !a.is_empty() && (a == stem || near_match(&a, &stem)) {
            return true;
        }
    }
    false
}

// ── o cliente dos VERBES (std-only — curto, Hello+Req+Ack) ───────────

/// O cliente de VERBO da dock: UMA conexão curta que se apresenta,
/// pede e espera o eco (a gramática da casa desde o C: conectar por
/// comando custa µs; a conexão PERSISTENTE é da thread de fundo).
/// O leitor é UMA thread de mentira de 1s de vida: lê os quadros do
/// daemon (boas-vindas + Ack) e entrega no canal; o dono do round-trip
/// filtra o que quer (Windows para a LIST, Ack para o verbo).
pub struct ToplevelClient {
    out: UnixStream,
    rx: std::sync::mpsc::Receiver<elite_core::BusMsg>,
    next_id: u32,
}

/// o tempo de vida do round-trip (o clique não espera nada além disso).
const RT_MS: u64 = 1000;

impl ToplevelClient {
    pub fn connect(path: &Path) -> Option<Self> {
        let mut stream = elite_core::ipc::connect_bus(path)?;
        elite_core::ipc::send_frame(
            &mut stream,
            &elite_core::BusMsg::Hello { who: "craft-dock-rs".into() },
        )
        .ok()?;
        let (tx, rx) = std::sync::mpsc::channel::<elite_core::BusMsg>();
        let mut leitor = stream.try_clone().ok()?;
        std::thread::spawn(move || {
            // o leitor do round-trip: vive enquanto alguém drena o canal
            // (o dono sai em ≤1s; o daemon morto fecha o fio sozinho)
            loop {
                match elite_core::ipc::recv_frame(&mut leitor) {
                    Ok(Some(msg)) => {
                        if tx.send(msg).is_err() {
                            return;
                        }
                    }
                    _ => return,
                }
            }
        });
        Some(Self { out: stream, rx, next_id: 1 })
    }

    fn pede(&mut self, req: elite_core::BusReq) -> Option<u32> {
        let id = self.next_id;
        self.next_id += 1;
        elite_core::ipc::send_frame(
            &mut self.out,
            &elite_core::BusMsg::Req { id, req },
        )
        .ok()?;
        Some(id)
    }

    /// LIST (a prova fresca do clique E135): espera o Windows do
    /// snapshot (as boas-vindas do Hello já contêm — o Req::Snapshot é
    /// o cinto para o daemon de era nova que demora na cortesia).
    pub fn list(&mut self) -> Option<Snapshot> {
        let _ = self.pede(elite_core::BusReq::Snapshot)?;
        let limite = std::time::Duration::from_millis(RT_MS);
        let inicio = std::time::Instant::now();
        while inicio.elapsed() < limite {
            match self.rx.recv_timeout(std::time::Duration::from_millis(100)) {
                Ok(elite_core::BusMsg::Windows { windows }) => {
                    return Some(de_bus_windows(&windows));
                }
                Ok(_) => continue, // boas-vindas demais: segue pescando
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return None,
            }
        }
        None
    }

    /// o verbo confirmado (o Ack ecoa o id; o efeito mora no snapshot
    /// que o bus publica a seguir — a fonte da verdade é sempre ela).
    fn verbo(&mut self, req: elite_core::BusReq) -> bool {
        let Some(id) = self.pede(req) else { return false };
        let limite = std::time::Duration::from_millis(RT_MS);
        let inicio = std::time::Instant::now();
        while inicio.elapsed() < limite {
            match self.rx.recv_timeout(std::time::Duration::from_millis(100)) {
                Ok(elite_core::BusMsg::Ack { id: eco, ok }) => {
                    // Ack de pedidos ANTERIORES (o Snapshot do list) é
                    // ruído honesto de fila: o eco que vale é o MEU id
                    if eco == id {
                        return ok;
                    }
                }
                Ok(_) => continue,
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return false,
            }
        }
        false
    }

    /// Foco/restauro POR ID (activate + unset_minimized no daemon).
    pub fn act(&mut self, id: u64) -> bool {
        self.verbo(elite_core::BusReq::Activate { id: id as u32 })
    }

    /// o toggle: MIN por id (o 2º clique no app focado minimiza).
    pub fn min(&mut self, id: u64) -> bool {
        self.verbo(elite_core::BusReq::Minimize { id: id as u32 })
    }

    /// CLOSE por id (o WM_DELETE gracioso — o clique do meio da dock).
    pub fn close_win(&mut self, id: u64) -> bool {
        self.verbo(elite_core::BusReq::Close { id: id as u32 })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use elite_core::bus::{BusClient, BusServer, Incoming};
    use elite_core::{BusMsg, BusReq, WindowInfo};
    use std::path::PathBuf;

    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("craft-dock-rs-sock-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    /// o WINDOWS de amostra da casa (a ordem é o anel MRU: 0 = topo).
    fn sample_windows() -> Vec<WindowInfo> {
        vec![
            WindowInfo { id: 10, app_id: "io.github.kolunmi.Bazaar".into(), title: Some("Bazaar — downloads".into()), focused: true, minimized: false, fullscreen: false, desk: None },
            WindowInfo { id: 11, app_id: "foot".into(), title: Some("foot".into()), focused: false, minimized: false, fullscreen: false, desk: None },
            WindowInfo { id: 12, app_id: "thunar".into(), title: Some("Arquivos — a|b|c".into()), focused: false, minimized: true, fullscreen: true, desk: None },
        ]
    }

    #[test]
    fn o_windows_do_bus_vira_o_snapshot_da_dock() {
        let snap = de_bus_windows(&sample_windows());
        assert_eq!(snap.windows.len(), 3);
        assert_eq!(snap.focused, 10);
        let b = &snap.windows[&10];
        assert_eq!(b.app_id, "io.github.kolunmi.Bazaar");
        assert_eq!(b.flags, F_ACTIVATED);
        assert_eq!(b.rank, 0); // índice 0 = topo do MRU
        let f = &snap.windows[&11];
        assert_eq!(f.rank, 1);
        let t = &snap.windows[&12];
        // o título com PIPE segue inteiro (None/Some é do fio, a dock
        // vive de String)
        assert_eq!(t.title, "Arquivos — a|b|c");
        assert_eq!(t.flags, F_MINIMIZED | F_FULLSCREEN);
        // LIST vazio VÁLIDO: focada 0, sem janelas (a graça do vazio E71
        // mora em QUEM aplica o snapshot, não no parse)
        let vazio = de_bus_windows(&[]);
        assert!(vazio.windows.is_empty());
        assert_eq!(vazio.focused, 0);
        // o título None do fio vira vazio (a gramática interna)
        let sem_titulo = de_bus_windows(&[WindowInfo { id: 1, app_id: "x".into(), title: None, focused: false, minimized: false, fullscreen: false, desk: None }]);
        assert_eq!(sem_titulo.windows[&1].title, "");
    }

    #[test]
    fn as_formas_canonicas_do_casamento_seguinto_intactas() {
        assert_eq!(
            case_variants("brave-browser"),
            vec!["brave-browser", "Brave-Browser"]
        );
        assert_eq!(case_variants("foot"), vec!["foot", "Foot"]);
        assert!(near_match("brave", "brave-browser"));
        assert!(near_match("brave-browser-stable", "brave"));
        assert!(!near_match("foot", "footclient"));
        assert!(!near_match("ab", "abc"));
    }

    #[test]
    fn near_match_com_fronteira() {
        assert!(near_match("brave", "brave-browser"));
        assert!(!near_match("foot", "footclient")); // letra colada
        assert!(!near_match("ab", "abc")); // <4 chars
        // 1.0-106 — o HÍFEN é fronteira: 'foot' casa 'foot-server' (a
        // mesma família de terminal — o WMClass/comm do daemon casa o
        // botão do foot para o AGRUPAMENTO), mas a letra colada do
        // footclient continua sendo OUTRO app
        assert!(near_match("foot", "foot-server"));
    }

    /// E106/2 — A REGRESSÃO DA SEGUNDA INSTÂNCIA: com a janela do app no
    /// snapshot, o esquerdo é VERBO de foco (Activate/Minimize por id),
    /// NUNCA um lançamento — a cadeia que decide no on_left: janela
    /// presente no snapshot + guard aposentado pelo MAP. O launch só mora
    /// no ramo do VAZIO comprovado (a LIST fresca E135 no clique).
    #[test]
    fn e106_o_clique_com_janela_e_verbo_nunca_lancamento() {
        let snap = de_bus_windows(&[WindowInfo {
            id: 21,
            app_id: "thunar".into(),
            title: Some("Arquivos — a|b".into()),
            focused: true,
            minimized: false,
            fullscreen: false,
            desk: None,
        }]);
        let cands = vec!["thunar".to_string()];
        // a janela do app está no snapshot: o esquerdo veste o verbo de
        // foco — o clique NÃO passa pelo launch (nada de 2ª instância)
        assert_eq!(windows_of_key(&snap, &cands, "Thunar", false), vec![21]);
        assert_eq!(windows_of_key(&snap, &cands, "Thunar", true), vec![21]);
        // a focada + não minimizada: o TOGGLE E89 manda MIN por id
        assert!(snap.windows[&21].flags & F_ACTIVATED != 0);
        assert!(snap.windows[&21].flags & F_MINIMIZED == 0);
        // o guard E88 aposenta (mapeou = o vão acabou): o clique seguinte
        // é foco imediato, nunca um novo processo
        assert!(key_mapped(&snap, "thunar.desktop"));
        // o SEM-NOME idem: a janela cravada é a prova (o raw nunca lança
        // às cegas — o Act::Raw sem janela é o log que ensina)
        assert_eq!(raw_windows(&snap, "thunar", false), vec![21]);
        assert_eq!(raw_windows(&snap, "thunar", true), vec![21]);
        // o VAZIO comprovado é o ÚNICO caminho de lançamento: sem janela
        // no snapshot fresco, o guard E71 protege o vão de 8s
        let vazio = de_bus_windows(&[]);
        assert!(windows_of_key(&vazio, &cands, "Thunar", false).is_empty());
        assert!(!key_mapped(&vazio, "thunar.desktop"));
    }

    #[test]
    fn e134_a_norma_do_travessao_agrupa_o_pin_com_o_aberto() {
        // O CASO DO DONO (dump 1.0-80): hydra_plus.desktop ↔ app_id
        // "hydra-plus" — '_' e '-' são O MESMO traço no casamento
        assert_eq!(norm("Hydra_Plus"), "hydra-plus");
        assert_eq!(norm("hydra-plus"), "hydra-plus");
        let snap = de_bus_windows(&[WindowInfo { id: 77, app_id: "hydra-plus".into(), title: Some("Hydra".into()), focused: true, minimized: false, fullscreen: false, desk: None }]);
        let cands = vec!["hydra_plus".to_string()];
        assert_eq!(windows_of_key(&snap, &cands, "", true), vec![77]);
        assert_eq!(raw_windows(&snap, "hydra_plus", true), vec![77]);
        assert!(key_mapped(&snap, "hydra_plus.desktop"));
        assert_eq!(norm("foot"), "foot");
        assert!(windows_of_key(&snap, &["foot".to_string()], "", true).is_empty());
    }

    #[test]
    fn janelas_do_app_no_snapshot() {
        let snap = de_bus_windows(&sample_windows());
        // o Bazaar do Flatpak: o app_id COMPLETO e o stem "bazaar" casam
        let cands = vec!["bazaar".to_string()];
        assert_eq!(windows_of_key(&snap, &cands, "", true), vec![10]);
        let cands2 = vec!["io.github.kolunmi.bazaar".to_string()];
        assert_eq!(windows_of_key(&snap, &cands2, "", true), vec![10]);
        // o título NUNCA casa em strict (lei E36: WM_DELETE sem risco)
        let thunar = vec!["thunar".to_string()];
        assert_eq!(windows_of_key(&snap, &thunar, "", true), vec![12]);
        // fora do strict, o nome de exibição no título é último recurso
        let nome = vec!["nao-existe".to_string()];
        assert!(windows_of_key(&snap, &nome, "Bazaar — downloads", false).contains(&10));
        assert!(windows_of_key(&snap, &nome, "Bazaar — downloads", true).is_empty());
        // o raw: stem composto da chave casa o app_id completo
        assert_eq!(raw_windows(&snap, "bazaar", true), vec![10]);
        assert_eq!(raw_windows(&snap, "kolunmi", true), Vec::<u64>::new());
        // a chave do lançamento mapeou? (E88)
        assert!(key_mapped(&snap, "io.github.kolunmi.Bazaar.desktop"));
        assert!(key_mapped(&snap, "foot"));
        assert!(!key_mapped(&snap, "nao-existe.desktop"));
    }

    #[test]
    fn ciclo_do_anel_por_id() {
        let snap = de_bus_windows(&sample_windows());
        let wids = vec![10u64, 11, 12];
        // sem memória: a focada (10, flag activated)
        assert_eq!(cycle_next(&snap, &wids, None), Some(10));
        // com memória: a PRÓXIMA da última que focamos (anel)
        assert_eq!(cycle_next(&snap, &wids, Some(10)), Some(11));
        assert_eq!(cycle_next(&snap, &wids, Some(12)), Some(10)); // dá a volta
        // memória fora do anel: ignora e segue a regra
        assert_eq!(cycle_next(&snap, &wids, Some(99)), Some(10));
        assert_eq!(cycle_next(&snap, &[], Some(1)), None);
    }

    /// O DAEMON FALSO que fala o protocolo do bus: Hello → boas-vindas
    /// (Windows) + Req → Ack (o circuito inteiro da Fase 2 em miniatura).
    #[test]
    fn cliente_contra_o_daemon_falso_do_bus() {
        let dir = tmpdir("bus");
        let sock = dir.join("bus.sock");
        let (srv, rx_nucleo) = BusServer::start(&sock).unwrap();
        let srv_bg = std::sync::Arc::clone(&srv);
        // o núcleo de mentira: boas-vindas com o snapshot + eco dos verbos
        std::thread::spawn(move || {
            for msg in rx_nucleo {
                match msg {
                    Incoming::Hello { id, who } => {
                        // (a dock de mentira tem DOIS clientes: o do
                        // verbo "craft-dock-rs" e o de fundo "-bg")
                        assert!(who.starts_with("craft-dock-rs"), "quem é {who}?");
                        srv.send_to(id, &BusMsg::Windows { windows: sample_windows() });
                    }
                    Incoming::Req { cliente, req_id, req } => {
                        let ok = match req {
                            BusReq::Activate { id } | BusReq::Minimize { id } | BusReq::Close { id } => id != 999,
                            _ => true,
                        };
                        srv.send_to(cliente, &BusMsg::Ack { id: req_id, ok });
                    }
                }
            }
        });

        // o LIST fresco do clique: as boas-vindas bastam
        let mut cli = ToplevelClient::connect(&sock).unwrap();
        let snap = cli.list().unwrap();
        assert_eq!(snap.windows.len(), 3);
        assert_eq!(snap.focused, 10);
        assert_eq!(snap.windows[&12].flags, F_MINIMIZED | F_FULLSCREEN);

        // os VERBOS confirmados (id 999 é o joker que falha de propósito)
        assert!(cli.act(10));
        assert!(cli.min(10));
        assert!(cli.close_win(12));
        assert!(!cli.act(999));

        // a thread de FUNDO da dock: o BusClient persistente recebe o
        // Windows publicado (a remoção instantânea da Fase 2)
        let (_bg, rx_bg) = BusClient::connect(&sock, "craft-dock-rs-bg").unwrap();
        srv_bg.broadcast(&BusMsg::Windows { windows: vec![] });
        let msg = rx_bg.recv_timeout(std::time::Duration::from_secs(2)).unwrap();
        assert!(matches!(msg, BusMsg::Windows { .. }), "chegou {msg:?}");
        // socket ausente: None honesto (a dock nunca depende dele)
        assert!(ToplevelClient::connect(&dir.join("nao-existe.sock")).is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
