// ELITE · craft-dock-rs — icons.rs (E132). A IDENTIDADE e o ÍCONE de
// cada botão, em lógica PURA (std + sha2): nada de GTK aqui — este
// módulo compila e é TESTADO onde não há biblioteca gráfica nenhuma.
//
// O que mora aqui (a ordem do dono, degrau E132):
//   · o matching REVERSE-DNS dos Flatpaks — "io.github.kolunmi.Bazaar
//     .desktop" é também indexado como "bazaar" (o stem minúsculo do
//     último segmento): a janela cujo app_id é o id completo resolve o
//     .desktop do Flatpak, EXIBE "Bazaar" com o ícone oficial e NUNCA
//     vira botão raw (a ordem do dono: "nunca raw");
//   · a busca de ícones em /var/lib/flatpak/exports/share/icons E
//     ~/.local/share/flatpak/exports/share/icons (além dos temas
//     hicolor/Papirus e do /usr/share/icons) — o ícone oficial do
//     Flatpak mora lá, não no tema do usuário;
//   · a cadeia de resolução E130 herdada do craft-dock-gui (1:1):
//     tema (normalização fold '_'↔'-') → ícones steam → o que o Gear
//     Lever JÁ extraiu (~/.local/share/icons + Icon= do .desktop de
//     usuário) → o cache da casa (~/.cache/elite/appimage-icons) → o
//     .DirIcon do mount vivo → a EXTRAÇÃO em thread → o glifo honesto
//     (a parte GTK da cadeia mora no ui.rs; AQUI vivem as funções de
//     busca/arquivo que a cadeia chama);
//   · o mini-parser de .desktop (Name/Icon/Exec/StartupWMClass/
//     Terminal/NoDisplay/Hidden) e o índice comm→.desktop dos
//     dinâmicos (com as chaves reverse-DNS dos Flatpaks).
//
// ESCOPO HONESTO: aqui NÃO mora a sonda /proc do AppImage (procapp.rs)
// nem o protocolo de janelas (sock.rs) — cada corpo no seu lugar.
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// E130 — a normalização da casa para nomes de ícone (1:1 do Python):
/// minúsculas, '_' equivale a '-', espaços fora. O Hydra_Plus, o
/// hydra-plus e o hydraplus são O MESMO app para a busca.
pub fn fold(s: &str) -> String {
    s.to_lowercase().replace('_', "-").replace(' ', "")
}

/// E132 — O MATCHING REVERSE-DNS DOS FLATPAKS (a ordem do dono): dado
/// um desktop-id "io.github.kolunmi.Bazaar.desktop", devolve as chaves
/// alternativas pelas quais ele também é indexado — o STEM minúsculo
/// do último segmento ("bazaar") e o id completo sem o .desktop (nas
/// duas caixas: o app_id do compositor preserva a capitalização do id
/// real). É isso que faz a janela "io.github.kolunmi.Bazaar" achar o
/// botão certo com nome e ícone OFICIAIS — nunca raw.
pub fn reverse_dns_alternates(desktop_id: &str) -> Vec<String> {
    let id = desktop_id.strip_suffix(".desktop").unwrap_or(desktop_id);
    let mut out = Vec::new();
    if let Some(stem) = id.rsplit('.').next() {
        let stem = stem.to_lowercase();
        if !stem.is_empty() && stem != id.to_lowercase() {
            out.push(stem);
        }
    }
    if !id.is_empty() {
        out.push(id.to_string());
        let low = id.to_lowercase();
        if low != id {
            out.push(low);
        }
    }
    out.retain(|s| !s.is_empty());
    out.dedup();
    out
}

/// E130 — os nomes de TEMA que valem para a chave raw (steam em 1º:
/// "steam_app_<id>" → "steam_icon_<id>" e "steam").
pub fn steam_icon_candidates(key: &str) -> Vec<String> {
    if let Some(appid) = key.strip_prefix("steam_app_") {
        if !appid.is_empty() {
            return vec![format!("steam_icon_{appid}"), "steam".into()];
        }
    }
    Vec::new()
}

/// E130 — as variantes de nome para a consulta ao TEMA (o loop do
/// _make_raw_button: a chave, '_'→'-' e '-'→'_' — o fold da casa em
/// forma de lista).
pub fn theme_icon_candidates(key: &str) -> Vec<String> {
    let mut out = vec![key.to_string()];
    let d = key.replace('_', "-");
    let u = key.replace('-', "_");
    if d != key {
        out.push(d);
    }
    if u != key {
        out.push(u);
    }
    out.dedup();
    out
}

/// E132 — AS RAÍZES DE BUSCA de ícone por nome, na ordem da casa:
/// temas Papirus-Dark/Papirus/hicolor do sistema → os EXPORTS do
/// Flatpak (system e user — o ícone oficial mora lá) → /usr/share/
/// icons → ~/.local/share/icons (onde o Gear Lever escreve) →
/// /usr/share/pixmaps. As raízes inexistentes são descartadas pelo
/// chamador (busca barata, sem stat por candidato).
pub fn icon_roots(home: &Path) -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = Vec::new();
    for theme in ["Papirus-Dark", "Papirus", "hicolor"] {
        roots.push(PathBuf::from("/usr/share/icons").join(theme));
    }
    // E132 — os exports do Flatpak (a ordem do dono: busca em
    // /var/lib/flatpak/exports/share/icons e ~/.local/share/flatpak/
    // exports/share/icons).
    roots.push(PathBuf::from("/var/lib/flatpak/exports/share/icons"));
    roots.push(home.join(".local/share/flatpak/exports/share/icons"));
    roots.push(PathBuf::from("/usr/share/icons"));
    roots.push(home.join(".local/share/icons"));
    roots.push(PathBuf::from("/usr/share/pixmaps"));
    roots.dedup();
    roots
}

/// Extensões de ícone que a casa aceita (mesma lista do Python E130).
pub const ICON_EXTS: [&str; 3] = ["png", "svg", "svgz"];

/// E130/E132 — o arquivo de ícone com o nome dado nas raízes (busca
/// RECURSIVA — os exports do Flatpak e o hicolor são hierárquicos:
/// <tema>/<tamanho>/apps/<nome>.png). O casamento é pelo fold (o
/// '_'↔'-' da casa). Caminhada determinística (dirs ordenados) para o
/// teste ser estável.
pub fn find_icon_file(name: &str, roots: &[PathBuf]) -> Option<PathBuf> {
    let key = fold(name);
    if key.is_empty() {
        return None;
    }
    let mut stack: Vec<PathBuf> = roots.to_vec();
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        let mut items: Vec<_> = entries.flatten().collect();
        items.sort_by_key(|e| e.file_name());
        for e in items {
            let p = e.path();
            if p.is_dir() {
                stack.push(p);
            } else if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
                let ext = p
                    .extension()
                    .and_then(|s| s.to_str())
                    .map(|s| s.to_lowercase())
                    .unwrap_or_default();
                if !ICON_EXTS.contains(&ext.as_str()) {
                    continue;
                }
                // E132 — o MATCHING REVERSE-DNS (a ordem do dono): o arquivo
                // oficial do Flatpak chama-se 'io.github.kolunmi.Bazaar.png'
                // e a busca da casa é pela chave CURTA 'bazaar' — casa o
                // fold inteiro OU o ÚLTIMO segmento do domínio
                let f = fold(stem);
                let last = f.rsplit('.').next().unwrap_or("");
                if f == key || (f.contains('.') && !last.is_empty() && last == key) {
                    return Some(p);
                }
            }
        }
    }
    None
}

/// E130 — O ÍCONE QUE O GEAR LEVER JÁ EXTRAÍU (sem trabalho novo):
/// ~/.local/share/icons/**/<nome>.png|svg e o Icon= do
/// ~/.local/share/applications/*.desktop de usuário que casa com a
/// chave (nome do arquivo, StartupWMClass ou o próprio Icon).
/// 1:1 do _gearlever_icon do Python.
pub fn gearlever_icon(key: &str, home: &Path) -> Option<PathBuf> {
    let k = fold(key);
    let icons_root = home.join(".local/share/icons");
    if let Some(hit) = find_icon_file(key, &[icons_root]) {
        return Some(hit);
    }
    let apps = home.join(".local/share/applications");
    let mut entries: Vec<_> = std::fs::read_dir(&apps)
        .ok()?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("desktop"))
        .collect();
    entries.sort();
    for path in entries {
        let Ok(txt) = std::fs::read_to_string(&path) else {
            continue;
        };
        let entry = parse_desktop_entry(&path.to_string_lossy(), &txt);
        let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        let mut cand_names = vec![fold(stem)];
        if !entry.wm_class.is_empty() {
            cand_names.push(fold(&entry.wm_class));
        }
        if !entry.icon.is_empty() {
            cand_names.push(fold(&entry.icon));
        }
        if !cand_names.contains(&k) {
            continue;
        }
        if !entry.icon.is_empty() {
            let icon_path = Path::new(&entry.icon);
            if icon_path.is_file() {
                return Some(icon_path.to_path_buf());
            }
            if let Some(hit) = find_icon_file(&entry.icon, &[home.join(".local/share/icons")]) {
                return Some(hit);
            }
        }
    }
    None
}

/// E130 — o caminho CACHEADO do ícone extraído do AppImage:
/// <cache_base>/<sha256-do-caminho[0..24]>.<png|svg> — o MESMO formato
/// do craft-dock-gui (hexdigest truncado em 24): os dois binários
/// COMPARTILHAM o cache (o ícone extraído por um serve ao outro).
/// Cria o diretório (a extração depende dele).
pub fn appicon_cache_path(cache_base: &Path, appimage: &str) -> PathBuf {
    let mut h = Sha256::new();
    h.update(appimage.as_bytes());
    let digest = format!("{:x}", h.finalize());
    let ext = if appimage.to_lowercase().ends_with(".svg") { "svg" } else { "png" };
    let _ = std::fs::create_dir_all(cache_base);
    cache_base.join(format!("{}.{}", &digest[..24], ext))
}

// ── o mini-parser de .desktop (E132 — os dinâmicos e os Flatpaks) ─────

/// Um .desktop da casa: só o que a dock LÊ (Name, Icon, Exec,
/// StartupWMClass, Terminal, NoDisplay/Hidden). O campo `id` é o nome
/// do arquivo (ex.: "io.github.kolunmi.Bazaar.desktop").
#[derive(Debug, Default, Clone)]
pub struct DesktopEntry {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub exec: String,
    pub wm_class: String,
    pub terminal: bool,
    pub no_display: bool,
    pub hidden: bool,
}

/// Parseia o corpo de um .desktop (a seção [Desktop Entry]; chaves
/// fora dela são IGNORADAS — mesmo recorte do Gio.DesktopAppInfo que o
/// Python usava). Puro e testado: alimentar texto é tudo que exige.
pub fn parse_desktop_entry(id: &str, text: &str) -> DesktopEntry {
    let mut e = DesktopEntry {
        id: id.to_string(),
        ..Default::default()
    };
    let mut in_main = false;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_main = line.eq_ignore_ascii_case("[Desktop Entry]");
            continue;
        }
        if !in_main {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let v = v.trim();
            match k.trim() {
                "Name" => e.name = v.to_string(),
                "Icon" => e.icon = v.to_string(),
                "Exec" => e.exec = v.to_string(),
                "StartupWMClass" => e.wm_class = v.to_string(),
                "Terminal" => e.terminal = v.eq_ignore_ascii_case("true"),
                "NoDisplay" => e.no_display = v.eq_ignore_ascii_case("true"),
                "Hidden" => e.hidden = v.eq_ignore_ascii_case("true"),
                _ => {}
            }
        }
    }
    e
}

/// Varre um diretório de .desktops (ex.: /usr/share/applications ou os
/// exports do Flatpak). NoDisplay/Hidden NUNCA entram (a lei E21 da
/// gaveta, herdada: helper rodando não é app de dock).
pub fn scan_desktop_dir(dir: &Path) -> Vec<DesktopEntry> {
    let mut out = Vec::new();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return out;
    };
    let mut paths: Vec<_> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("desktop"))
        .collect();
    paths.sort();
    for p in paths {
        let Ok(txt) = std::fs::read_to_string(&p) else {
            continue;
        };
        let id = p.file_name().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        let e = parse_desktop_entry(&id, &txt);
        if e.no_display || e.hidden {
            continue;
        }
        out.push(e);
    }
    out
}

/// Os diretórios de .desktop que a casa varre (E132 — os EXPORTS do
/// Flatpak ANTES do sistema: o Flatpak instalado pelo usuário mora no
/// export dele, não em /usr/share/applications).
pub fn desktop_dirs(home: &Path) -> Vec<PathBuf> {
    vec![
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        home.join(".local/share/flatpak/exports/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
        PathBuf::from("/usr/share/applications"),
        home.join(".local/share/applications"),
    ]
}

/// E132 — o ÍNDICE de .desktops: chave (fold) → entrada. As chaves de
/// cada entrada: StartupWMClass, o 1º binário do Exec, o id sem o
/// .desktop E as alternativas REVERSE-DNS ("bazaar" para o
/// io.github.kolunmi.Bazaar.desktop — a ordem do dono). A PRIMEIRA
/// chave vence (setdefault do Python).
pub fn desktop_index(entries: &[DesktopEntry]) -> HashMap<String, usize> {
    let mut idx: HashMap<String, usize> = HashMap::new();
    for (i, e) in entries.iter().enumerate() {
        let mut keys: Vec<String> = Vec::new();
        if !e.wm_class.is_empty() {
            keys.push(fold(&e.wm_class));
        }
        let bin = first_binary(&strip_field_codes(&e.exec));
        if let Some(b) = bin {
            keys.push(fold(&b));
        }
        keys.extend(reverse_dns_alternates(&e.id).iter().map(|k| fold(k)));
        for k in keys {
            if k.is_empty() {
                continue;
            }
            idx.entry(k).or_insert(i);
        }
    }
    idx
}

/// Resolve uma chave (comm, app_id, stem) no índice — a gramática do
/// _resolve_desktop do Python: exato → stem do id composto →
/// contenção com fronteira (near_match, do sock.rs). None = não é
/// "programa" no sentido da dock (raw/sem botão).
pub fn resolve_desktop<'a>(
    idx: &HashMap<String, usize>,
    entries: &'a [DesktopEntry],
    key: &str,
) -> Option<&'a DesktopEntry> {
    let c = key.to_lowercase();
    if c.is_empty() {
        return None;
    }
    if let Some(i) = idx.get(&fold(&c)) {
        return Some(&entries[*i]);
    }
    if let Some(stem) = c.rsplit('.').next() {
        if let Some(i) = idx.get(&fold(stem)) {
            return Some(&entries[*i]);
        }
    }
    // contenção com fronteira (a lei v2.10.6: 'brave' ⊂ 'brave-browser'
    // casa; 'foot' ⊂ 'footclient' NÃO — letra colada é outro app)
    let mut best: Option<usize> = None;
    for (k, i) in idx {
        if crate::sock::near_match(&c, k) {
            best = Some(*i);
            break;
        }
    }
    best.map(|i| &entries[i])
}

// ── os verbos do Exec (portados do raw_of/exec_of/binary_of) ──────────

/// O Commandline do .desktop SEM os códigos de campo (%f %U …) e SEM
/// o casaco do terminal — a PROVA DE ORIGEM para casar janelas (o
/// comm do /proc fala o nome do APP, nunca o do foot que o carrega).
pub fn strip_field_codes(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut chars = raw.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' {
            // %X (um código de campo) some junto com o espaço ANTES dele
            if chars.peek().map_or(false, |n| n.is_ascii_alphabetic()) {
                chars.next();
                // o espaço precedente só é comido se existia
                if out.ends_with(' ') {
                    out.pop();
                }
                continue;
            }
        }
        out.push(c);
    }
    out.trim().to_string()
}

/// O Commandline PRONTO PARA NASCER: Terminal=true veste o foot da
/// casa com app-id DETERMINÍSTICO (o binário do app — o casamento de
/// janelas fala ESSE nome). E94 do Python, 1:1.
pub fn exec_ready(entry: &DesktopEntry) -> String {
    let raw = strip_field_codes(&entry.exec);
    if raw.is_empty() {
        return raw;
    }
    if entry.terminal && !raw.starts_with("foot") {
        if let Some(nome) = first_binary(&raw) {
            return format!("foot --app-id={nome} /usr/bin/env -S {raw}");
        }
    }
    raw
}

/// O 1º binário do commandline (shlex do Python: aqui, um split
/// simples por espaço — os Exec da casa não citam o 1º token).
pub fn first_binary(raw: &str) -> Option<String> {
    let first = raw.split_whitespace().next()?;
    Some(Path::new(first).file_name()?.to_string_lossy().into_owned())
}

// ── a chave do botão RAW (E106 — a denylist dos diálogos de daemon) ──

/// E106 — janela de DAEMON/diálogo de sistema não é aplicativo: o
/// diálogo do chaveiro (gcr-prompter), os agentes polkit, o zenity e
/// o OSD NUNCA ganham botão na dock (a mesa é de PROGRAMAS).
pub const RAW_DENY_STEMS: [&str; 6] = [
    "gcr-prompter",
    "lxqt-policykit",
    "polkit-gnome",
    "zenity",
    "swayosd",
    "hyprpolkitagent",
];

/// A chave do SEM-NOME (o _raw_key do Python, 1:1): app_id em
/// minúsculas com o STEM composto; sem app_id, o título (truncado —
/// churn de título documentado). None = denylist ou nada a expor.
pub fn raw_key(app_id: &str, title: &str) -> Option<(String, String)> {
    let a = app_id.trim().to_lowercase();
    let t = title.trim().to_lowercase();
    let stem_cand: String = if !a.is_empty() {
        a.rsplit('.').next().unwrap_or("").to_string()
    } else {
        t.chars().take(24).collect()
    };
    // E106 — a denylist morde o STEM do app_id E o começo do TÍTULO (o
    // dump 20261112: 'raw entrou: polkit-gnome-agent' — o app_id era o
    // domínio polido do polkit, o título era quem entregava o diálogo)
    if !stem_cand.is_empty() && raw_deny_match(&stem_cand) {
        return None;
    }
    let t_stem: String = t.chars().take(24).collect();
    if !t_stem.is_empty() && raw_deny_match(&t_stem) {
        return None;
    }
    if !a.is_empty() {
        let stem = a.rsplit('.').next().unwrap_or("");
        return if stem.chars().count() >= 2 {
            Some((stem.to_string(), a))
        } else {
            Some((a.clone(), a))
        };
    }
    if t.is_empty() {
        return None;
    }
    let k: String = t.chars().take(24).collect();
    let n: String = t.chars().take(40).collect();
    Some((k, n))
}

fn raw_deny_match(stem: &str) -> bool {
    RAW_DENY_STEMS.iter().any(|d| stem.starts_with(d))
}

// ── os candidatos de foco (o _focus_candidates do Python, + E132) ────

/// Ordem de adivinha do foco: hint explícito do pin → StartupWMClass
/// → binário do Exec → stem do desktop-id → as alternativas
/// REVERSE-DNS (E132: o app_id completo do Flatpak casa com o id
/// inteiro, não só com o stem "bazaar"). Dedup preservando a ordem.
pub fn focus_candidates(entry: &DesktopEntry, hint: &str) -> Vec<String> {
    let mut cands: Vec<String> = Vec::new();
    if !hint.is_empty() {
        cands.push(hint.to_string());
    }
    if !entry.wm_class.is_empty() {
        cands.push(entry.wm_class.clone());
    }
    if let Some(b) = first_binary(&strip_field_codes(&entry.exec)) {
        cands.push(b);
    }
    cands.extend(reverse_dns_alternates(&entry.id));
    let mut out: Vec<String> = Vec::new();
    for c in cands {
        if !c.is_empty() && !out.contains(&c) {
            out.push(c);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("craft-dock-rs-icons-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn e132_fold_e_a_cadeia_de_normalizacao() {
        // o Hydra_Plus, o hydra-plus e o hydra plus são O MESMO app
        assert_eq!(fold("Hydra_Plus"), "hydra-plus");
        assert_eq!(fold("hydra-plus"), "hydra-plus");
        assert_eq!(fold("Hydra Plus"), "hydraplus");
    }

    #[test]
    fn e132_reverse_dns_do_flatpak() {
        // a ordem do dono: o Bazaar do kolunmi é indexado como "bazaar"
        let alts = reverse_dns_alternates("io.github.kolunmi.Bazaar.desktop");
        assert_eq!(alts[0], "bazaar");
        assert!(alts.contains(&"io.github.kolunmi.Bazaar".to_string()));
        assert!(alts.contains(&"io.github.kolunmi.bazaar".to_string()));
        // id simples: só ele mesmo (o stem == id não duplica)
        assert_eq!(
            reverse_dns_alternates("foot.desktop"),
            vec!["foot".to_string()]
        );
    }

    #[test]
    fn e132_steam_e_variantes_de_tema() {
        assert_eq!(
            steam_icon_candidates("steam_app_1234"),
            vec!["steam_icon_1234", "steam"]
        );
        assert!(steam_icon_candidates("hydra-plus").is_empty());
        let mut c = theme_icon_candidates("hydra_plus");
        assert!(c.contains(&"hydra-plus".to_string()));
        c = theme_icon_candidates("hydra-plus");
        assert!(c.contains(&"hydra_plus".to_string()));
    }

    #[test]
    fn e132_raizes_incluem_os_exports_do_flatpak() {
        let home = PathBuf::from("/home/dono");
        let roots = icon_roots(&home);
        // a ordem do dono: system e user ANTES do /usr/share/icons puro
        assert!(roots.contains(&PathBuf::from("/var/lib/flatpak/exports/share/icons")));
        assert!(roots.contains(&home.join(".local/share/flatpak/exports/share/icons")));
        assert!(roots.contains(&home.join(".local/share/icons"))); // Gear Lever
        assert!(roots.contains(&PathBuf::from("/usr/share/icons")));
    }

    #[test]
    fn e132_busca_recursiva_casa_por_fold() {
        let root = tmpdir("find");
        let dir = root.join("hicolor/64x64/apps");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("io.github.kolunmi.Bazaar.png"), b"png").unwrap();
        std::fs::write(dir.join("outra-coisa.svg"), b"svg").unwrap();
        // o nome com caixa/underline diferente acha o oficial do Flatpak
        let hit = find_icon_file("bazaar", &[root.clone()]);
        assert_eq!(hit, Some(dir.join("io.github.kolunmi.Bazaar.png")));
        assert!(find_icon_file("nao-existe", &[root]).is_none());
    }

    #[test]
    fn e132_gearlever_icon_do_usuario() {
        let home = tmpdir("gearlever");
        let icons = home.join(".local/share/icons/hicolor/128x128/apps");
        std::fs::create_dir_all(&icons).unwrap();
        std::fs::write(icons.join("hydra-plus.png"), b"png").unwrap();
        assert_eq!(
            gearlever_icon("Hydra_Plus", &home),
            Some(icons.join("hydra-plus.png"))
        );
        // o Icon= do .desktop de usuário também é fonte (caso 2 do Python)
        let home2 = tmpdir("gearlever2");
        let apps = home2.join(".local/share/applications");
        std::fs::create_dir_all(&apps).unwrap();
        let icon_dir = home2.join(".local/share/icons/xyz");
        std::fs::create_dir_all(&icon_dir).unwrap();
        std::fs::write(icon_dir.join("bazaar-icon.png"), b"png").unwrap();
        std::fs::write(
            apps.join("io.github.kolunmi.Bazaar.desktop"),
            "[Desktop Entry]\nName=Bazaar\nIcon=bazaar-icon\nStartupWMClass=bazaar\n",
        )
        .unwrap();
        assert_eq!(
            gearlever_icon("bazaar", &home2),
            Some(icon_dir.join("bazaar-icon.png"))
        );
    }

    #[test]
    fn e130_cache_sha256_do_caminho() {
        let base = tmpdir("cache");
        let p = appicon_cache_path(&base, "/opt/Apps/Hydra Plus.AppImage");
        let name = p.file_name().unwrap().to_string_lossy().into_owned();
        assert!(name.ends_with(".png"));
        assert_eq!(name.len(), 24 + 1 + 3); // digest[0..24] + '.' + ext
        // o MESMO caminho → o MESMO nome (o cache é estável entre sessões)
        let p2 = appicon_cache_path(&base, "/opt/Apps/Hydra Plus.AppImage");
        assert_eq!(p, p2);
        // .svg no fim do caminho muda a extensão (o formato do arquivo)
        let s = appicon_cache_path(&base, "/x/app.svg");
        assert!(s.to_string_lossy().ends_with(".svg"));
        assert!(base.is_dir()); // o diretório nasce junto
    }

    #[test]
    fn e132_parse_e_indice_com_reverse_dns() {
        let txt = "[Desktop Entry]\nName=Bazaar\n\
                   Exec=bazaar --z %U\nIcon=io.github.kolunmi.Bazaar\n\
                   StartupWMClass=Bazaar\nType=Application\n";
        let e = parse_desktop_entry("io.github.kolunmi.Bazaar.desktop", txt);
        assert_eq!(e.name, "Bazaar");
        assert_eq!(e.wm_class, "Bazaar");
        assert_eq!(e.exec, "bazaar --z %U");
        // os códigos de campo saem (com o espaço que os carregava)
        assert_eq!(strip_field_codes(&e.exec), "bazaar --z");
        assert_eq!(first_binary(&e.exec).unwrap(), "bazaar");
        let entries = vec![e];
        let idx = desktop_index(&entries);
        // as chaves: wm_class, binário e as REVERSE-DNS (bazaar!)
        for k in ["bazaar", "io.github.kolunmi.bazaar"] {
            assert!(idx.contains_key(k), "faltou a chave {k}");
        }
        // o comm do /proc ("bazaar") resolve o .desktop — nunca raw
        let hit = resolve_desktop(&idx, &entries, "bazaar").unwrap();
        assert_eq!(hit.name, "Bazaar");
        // o app_id COMPLETO do compositor também resolve (o stem casa)
        assert!(resolve_desktop(&idx, &entries, "io.github.kolunmi.Bazaar").is_some());
        // NoDisplay/Hidden nunca entram no índice (lei E21)
        let nd = parse_desktop_entry(
            "x.desktop",
            "[Desktop Entry]\nName=X\nNoDisplay=true\nExec=x\n",
        );
        assert!(nd.no_display);
        assert!(scan_desktop_dir(Path::new("/caminho/que/nao/existe")).is_empty());
    }

    #[test]
    fn e94_exec_ready_veste_o_foot_para_tui() {
        let e = parse_desktop_entry(
            "btop.desktop",
            "[Desktop Entry]\nName=btop\nExec=btop\nTerminal=true\n",
        );
        assert_eq!(
            exec_ready(&e),
            "foot --app-id=btop /usr/bin/env -S btop"
        );
        // Terminal=false: o Exec cru
        let e2 = parse_desktop_entry(
            "thunar.desktop",
            "[Desktop Entry]\nName=Thunar\nExec=thunar %F\n",
        );
        assert_eq!(exec_ready(&e2), "thunar");
    }

    #[test]
    fn e106_raw_key_e_a_denylist_dos_dialogos() {
        // app_id composto → stem
        assert_eq!(
            raw_key("io.github.kolunmi.Bazaar", "Bazaar"),
            Some(("bazaar".into(), "io.github.kolunmi.bazaar".into()))
        );
        // sem app_id: o título é a única verdade (truncado)
        let (k, n) = raw_key("", "Um jogo Steam com título comprido demais").unwrap();
        assert_eq!(k.chars().count(), 24);
        assert!(n.chars().count() <= 40);
        // a denylist E106: diálogo de daemon NUNCA é botão
        assert!(raw_key("gcr-prompter", "Unlock Login Keyring").is_none());
        assert!(raw_key("org.freedesktop.polkit", "polkit-gnome-agent").is_none());
        assert!(raw_key("", "zenity — pergunta").is_none());
        assert!(raw_key("", "").is_none());
    }

    #[test]
    fn e132_focus_candidates_com_reverse_dns() {
        let e = parse_desktop_entry(
            "io.github.kolunmi.Bazaar.desktop",
            "[Desktop Entry]\nName=Bazaar\nExec=bazaar\nStartupWMClass=Bazaar\n",
        );
        let c = focus_candidates(&e, "");
        // wm_class, binário, stem e o id completo (E132) — dedup na ordem
        assert_eq!(
            c,
            vec![
                "Bazaar".to_string(),
                "bazaar".to_string(),
                "io.github.kolunmi.Bazaar".to_string(),
                "io.github.kolunmi.bazaar".to_string(),
            ]
        );
        // o hint explícito do pin vem PRIMEIRO (a 2ª coluna do dock-pins)
        let c2 = focus_candidates(&e, "kolunmi-bazaar");
        assert_eq!(c2[0], "kolunmi-bazaar");
    }
}
