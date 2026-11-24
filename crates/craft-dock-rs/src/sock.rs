// ELITE · craft-dock-rs — sock.rs (E132). O protocolo do craft-toplevel
// (vendor/craft-toplevel.c): a sessão de janelas REAIS servida linha a
// linha no toplevel.sock, e a GRAMÁTICA DE CASAMENTO da casa.
//
// O porto do craft-dock-gui v2.10.26/E38:
//   · LIST → "W|id|flags|rank|app_id|title"… + "OK|<focada>" — o
//     snapshot com o anel MRU do alt-tab (rank 0 = topo);
//   · ACT <id> / MIN <id> / CLOSE <id> — foco/restauro, o toggle de
//     minimizar (E89) e o WM_DELETE gracioso, POR ID (fim da
//     adivinhação de capitalização do wlrctl);
//   · EVT ON → "EVT" a cada batch de mudanças (o CANAL DE PUSH — a
//     leitura ASSÍNCRONA do toplevel.sock que o dono ordenou: uma
//     thread de fundo dorme no read e o MainContext acorda a UI).
//
// As flags do protocolo (o mapa completo, v2.10.26): 1=maximized ·
// 2=minimized · 4=activated · 8=fullscreen.
//
// Tudo aqui é std-only (UnixStream) e TESTADO com um daemon FALSO em
// temp dir — o parsing é função pura, o cliente fala com um listener
// de mentira que responde o payload da casa.
use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::time::Duration;

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
}

/// O snapshot LIST: janelas por id + a janela focada (0 = nenhuma).
#[derive(Debug, Clone, Default)]
pub struct Snapshot {
    pub windows: HashMap<u64, WindowEntry>,
    pub focused: u64,
}

/// Parseia as linhas de resposta do LIST (puro — o teste alimenta o
/// payload da casa direto). O título admite '|' (splitn de 6: o resto
/// é título, como no Python). "OK|<id>" fecha com a focada.
pub fn parse_list(lines: &[String]) -> Snapshot {
    let mut snap = Snapshot::default();
    for line in lines {
        if line.starts_with("W|") {
            let parts: Vec<&str> = line.splitn(6, '|').collect();
            if parts.len() == 6 {
                if let (Ok(id), Ok(flags), Ok(rank)) =
                    (parts[1].parse(), parts[2].parse(), parts[3].parse())
                {
                    snap.windows.insert(
                        id,
                        WindowEntry {
                            id,
                            flags,
                            rank,
                            app_id: parts[4].to_string(),
                            title: parts[5].to_string(),
                        },
                    );
                    continue;
                }
            }
        } else if let Some(rest) = line.strip_prefix("OK|") {
            if let Ok(f) = rest.trim().parse() {
                snap.focused = f;
            }
        }
    }
    snap
}

/// O byte do daemon é um EVENTO de mudança de janelas? (o canal EVT —
/// "EVT" em qualquer ponto do buffer acordado pela thread de fundo).
pub fn is_event(data: &[u8]) -> bool {
    data.windows(3).any(|w| w == b"EVT")
}

// ── a gramática de casamento da casa (v2.10.0→v2.10.6) ────────────────

/// v2.10 — as 3 formas canônicas de um candidato (original, minúscula,
/// título): o match do wlrctl era exato e case-sensitive ("Brave-
/// browser" nunca casava com "brave-browser"). Dedup na ordem.
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
        let mut from = 0usize;
        loop {
            let Some(hay) = y.get(from..) else { break };
            let Some(rel) = hay.find(x) else { break };
            let i = from + rel;
            let before_ok = y[..i].chars().next_back().map_or(true, |ch| !ch.is_alphanumeric());
            let after_ok = y[i + x.len()..].chars().next().map_or(true, |ch| !ch.is_alphanumeric());
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

// ── o cliente (std-only — o UnixStream da casa, SEM GTK) ──────────────

/// Um pedido linha-a-linha com o daemon, resposta = linhas até
/// OK*/ERR*/PONG. O _tl_cmd do Python: timeout de 1s, conexão
/// persistente mantida por quem chama (a thread de fundo da UI).
pub fn cmd_on(stream: &mut UnixStream, cmd: &str) -> Option<Vec<String>> {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
    stream.write_all(format!("{cmd}\n").as_bytes()).ok()?;
    let mut buf: Vec<u8> = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            return None; // daemon fechou
        }
        buf.extend_from_slice(&chunk[..n]);
        // resposta completa = termina em \n e a última linha é terminal
        if buf.ends_with(b"\n") {
            let lines: Vec<String> = buf
                .split(|&b| b == b'\n')
                .filter(|l| !l.is_empty())
                .map(|l| String::from_utf8_lossy(l).into_owned())
                .collect();
            if let Some(last) = lines.last() {
                if last.starts_with("OK") || last.starts_with("ERR") || last.starts_with("PONG") {
                    return Some(lines);
                }
            }
        }
    }
}

/// O cliente do toplevel.sock (a gramática por-comando da casa). Morreu?
/// O chamador reconstrói — a dock NUNCA depende dele.
pub struct ToplevelClient {
    path: PathBuf,
}

impl ToplevelClient {
    pub fn connect(path: &Path) -> Option<Self> {
        // a conexão é POR COMANDO (o molde do client Python: conecta,
        // pede, lê, fecha — o daemon-toplevel atende cada pedido numa
        // conexão própria). AQUI só se guarda o caminho: conectar sem
        // pedir consumiria um atendimento do daemon à toa.
        if !path.exists() {
            return None;
        }
        Some(Self { path: path.to_path_buf() })
    }

    /// Um pedido qualquer (linhas cruas da resposta) — UMA conexão nova
    /// por comando (a gramática do daemon: LIST/ACT/MIN/CLOSE vivem em
    /// conexões independentes).
    pub fn cmd(&mut self, cmd: &str) -> Option<Vec<String>> {
        let mut s = UnixStream::connect(&self.path).ok()?;
        cmd_on(&mut s, cmd)
    }

    /// LIST → snapshot (None = transporte morto; vazio VÁLIDO é Some).
    pub fn list(&mut self) -> Option<Snapshot> {
        self.cmd("LIST").map(|lines| parse_list(&lines))
    }

    /// Foco/restauro POR ID (unset_minimized + activate no daemon).
    pub fn act(&mut self, id: u64) -> bool {
        self.ok(&format!("ACT {id}"))
    }

    /// E89 — o toggle: MIN por id (set_minimized; o 2º clique no app
    /// focado minimiza, a gramática de toda dock do mundo).
    pub fn min(&mut self, id: u64) -> bool {
        self.ok(&format!("MIN {id}"))
    }

    /// CLOSE por id (WM_DELETE gracioso — o app confirma se tiver o
    /// que salvar).
    pub fn close_win(&mut self, id: u64) -> bool {
        self.ok(&format!("CLOSE {id}"))
    }

    fn ok(&mut self, cmd: &str) -> bool {
        self.cmd(cmd)
            .map(|out| out.last().map(|l| l.starts_with("OK")).unwrap_or(false))
            .unwrap_or(false)
    }
}

/// E38 — o handshake do CANAL DE EVENTOS: "EVT ON\n" → "OK" (daemon
/// velho responde outra coisa: o chamador fecha e segue no tick — a
/// lei do fallback nunca depende de recurso novo).
pub fn evt_handshake(stream: &mut UnixStream) -> bool {
    let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
    if stream.write_all(b"EVT ON\n").is_err() {
        return false;
    }
    let mut buf = [0u8; 64];
    match stream.read(&mut buf) {
        Ok(n) if n > 0 => buf.starts_with(b"OK"),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::net::UnixListener;
    use std::path::PathBuf;

    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("craft-dock-rs-sock-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn sample_lines() -> Vec<String> {
        vec![
            "W|10|4|0|io.github.kolunmi.Bazaar|Bazaar — downloads".into(),
            "W|11|0|1|foot|foot".into(),
            // título com PIPE: o splitn(6) preserva o resto como título
            "W|12|2|2|thunar|Arquivos — a|b|c".into(),
            "W|lixo|1|1|x|y".into(), // id inválido: linha ignorada
            "OK|10".into(),
        ]
    }

    #[test]
    fn parse_do_list_da_casa() {
        let snap = parse_list(&sample_lines());
        assert_eq!(snap.windows.len(), 3);
        assert_eq!(snap.focused, 10);
        let b = &snap.windows[&10];
        assert_eq!(b.app_id, "io.github.kolunmi.Bazaar");
        assert_eq!(b.flags, F_ACTIVATED);
        assert_eq!(b.rank, 0);
        let t = &snap.windows[&12];
        assert_eq!(t.title, "Arquivos — a|b|c"); // o pipe fica no título
        assert_eq!(t.flags, F_MINIMIZED);
        // LIST vazio VÁLIDO: focada 0, sem janelas (a graça do vazio E71
        // mora em QUEM aplica o snapshot, não no parse)
        let vazio = parse_list(&["OK|0".to_string()]);
        assert!(vazio.windows.is_empty());
        assert_eq!(vazio.focused, 0);
    }

    #[test]
    fn evt_e_as_formas_canonicas() {
        assert!(is_event(b"OK\nEVT\n"));
        assert!(is_event(b"EVT"));
        assert!(!is_event(b"W|1|0|0|foot|foot\nOK|1\n"));
        assert_eq!(
            case_variants("brave-browser"),
            vec!["brave-browser", "Brave-Browser"]
        );
        assert_eq!(
            case_variants("foot"),
            vec!["foot", "Foot"]
        );
    }

    #[test]
    fn near_match_com_fronteira() {
        assert!(near_match("brave", "brave-browser"));
        assert!(near_match("brave-browser-stable", "brave")); // dois sentidos
        assert!(!near_match("foot", "footclient")); // letra colada
        assert!(!near_match("ab", "abc")); // <4 chars
    }

    #[test]
    fn e134_a_norma_do_travessao_agrupa_o_pin_com_o_aberto() {
        // O CASO DO DONO (dump 1.0-80): hydra_plus.desktop ↔ app_id
        // "hydra-plus" — '_' e '-' são O MESMO traço no casamento
        assert_eq!(norm("Hydra_Plus"), "hydra-plus");
        assert_eq!(norm("hydra-plus"), "hydra-plus");
        // o snapshot de mentira com a janela do Hydra
        let linhas: Vec<String> = vec![
            "W|77|4|0|hydra-plus|Hydra".into(),
            "OK|77".into(),
        ];
        let snap = parse_list(&linhas);
        // o stem do pin (hydra_plus) casa a janela (hydra-plus) —
        // pin + aberto são UM botão só (o exato normativo)
        let cands = vec!["hydra_plus".to_string()];
        assert_eq!(windows_of_key(&snap, &cands, "", true), vec![77]);
        // o raw idem: a chave do comm com '_' veste o app_id com '-'
        assert_eq!(raw_windows(&snap, "hydra_plus", true), vec![77]);
        // e o guard do lançamento mapeia pelo desktop-id com '_'
        assert!(key_mapped(&snap, "hydra_plus.desktop"));
        // a NORMA não dissolve apps diferentes: foot ≠ foot-client no
        // exato (o near com fronteira continua sendo a única ponte)
        assert_eq!(norm("foot"), "foot");
        assert!(windows_of_key(&snap, &["foot".to_string()], "", true).is_empty());
    }

    #[test]
    fn janelas_do_app_no_snapshot() {
        let snap = parse_list(&sample_lines());
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
        let snap = parse_list(&sample_lines());
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

    #[test]
    fn cliente_contra_o_daemon_falso() {
        let dir = tmpdir("mock");
        let sock = dir.join("toplevel.sock");
        let listener = UnixListener::bind(&sock).unwrap();
        let servidor = std::thread::spawn(move || {
            // um atendimento POR conexão (a gramática do client: cada
            // comando vive numa conexão própria — LIST, ACT, MIN, CLOSE)
            for _ in 0..4 {
                let Ok((mut conn, _)) = listener.accept() else { break };
                let mut buf = [0u8; 256];
                let n = conn.read(&mut buf).unwrap();
                let pedido = String::from_utf8_lossy(&buf[..n]).trim().to_string();
                let resposta = if pedido == "LIST" {
                    let mut s = String::new();
                    for l in sample_lines() {
                        s.push_str(&l);
                        s.push('\n');
                    }
                    s
                } else {
                    "OK\n".to_string()
                };
                conn.write_all(resposta.as_bytes()).unwrap();
            }
        });
        let mut cli = ToplevelClient::connect(&sock).unwrap();
        let snap = cli.list().unwrap();
        assert_eq!(snap.windows.len(), 3);
        assert_eq!(snap.focused, 10);
        assert!(cli.act(10));
        assert!(cli.min(10));
        assert!(cli.close_win(12));
        servidor.join().unwrap();
        // socket ausente: None honesto (a dock nunca depende dele)
        assert!(ToplevelClient::connect(&dir.join("nao-existe.sock")).is_none());
    }

    #[test]
    fn handshake_do_canal_de_eventos() {
        let dir = tmpdir("evt");
        let sock = dir.join("evt.sock");
        let listener = UnixListener::bind(&sock).unwrap();
        let servidor = std::thread::spawn(move || {
            let (mut conn, _) = listener.accept().unwrap();
            let mut buf = [0u8; 64];
            let n = conn.read(&mut buf).unwrap();
            assert_eq!(String::from_utf8_lossy(&buf[..n]).trim(), "EVT ON");
            conn.write_all(b"OK\n").unwrap();
            // o push do daemon: um EVT depois do handshake
            std::thread::sleep(Duration::from_millis(50));
            let _ = conn.write_all(b"EVT\n");
        });
        let mut s = UnixStream::connect(&sock).unwrap();
        assert!(evt_handshake(&mut s));
        let mut buf = [0u8; 64];
        let n = s.read(&mut buf).unwrap();
        assert!(is_event(&buf[..n]));
        servidor.join().unwrap();
    }
}
