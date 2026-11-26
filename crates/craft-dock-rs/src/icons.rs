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

/// E133 — extensões de IMAGEM amplas para os CACHES DE JOGO (Steam/
/// Lutris/Heroic/Hydra guardam .ico/.xpm/.jpg/.bmp que o GdkPixbuf
/// lê de boa — a lista restrita ICON_EXTS vale para a busca de TEMA,
/// onde só png/svg é convenção de verdade).
pub const IMAGE_EXTS: [&str; 8] = ["png", "svg", "svgz", "ico", "xpm", "jpg", "jpeg", "bmp"];

/// E130/E132 — o arquivo de ícone com o nome dado nas raízes (busca
/// RECURSIVA — os exports do Flatpak e o hicolor são hierárquicos:
/// <tema>/<tamanho>/apps/<nome>.png). O casamento é pelo fold (o
/// '_'↔'-' da casa). Caminhada determinística (dirs ordenados) para o
/// teste ser estável.
pub fn find_icon_file(name: &str, roots: &[PathBuf]) -> Option<PathBuf> {
    find_by_fold(name, roots, &ICON_EXTS)
}

/// E133 — a mesma busca por fold com a lista de imagens AMPLA (os
/// caches de jogo: .ico do Steam, .jpg da librarycache, .xpm antigo —
/// o GdkPixbuf exibe todos e o dono vê a capa que a loja já baixou).
pub fn find_image_file(name: &str, roots: &[PathBuf]) -> Option<PathBuf> {
    find_by_fold(name, roots, &IMAGE_EXTS)
}

/// O coração da busca (ICON_EXTS e IMAGE_EXTS são a MESMA máquina):
/// caminhada por pilha com dirs ordenados; o casamento é o fold
/// inteiro OU o ÚLTIMO segmento do domínio reverse-DNS (o arquivo
/// oficial 'io.github.kolunmi.Bazaar.png' casa com a chave 'bazaar').
fn find_by_fold(name: &str, roots: &[PathBuf], exts: &[&str]) -> Option<PathBuf> {
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
                if !exts.contains(&ext.as_str()) {
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
/// do craft-dock-gui aposentado E134 (hexdigest truncado em 24): os
/// rigs conservam o cache que a era Python já extraiu.
/// Cria o diretório (a extração depende dele).
pub fn appicon_cache_path(cache_base: &Path, appimage: &str) -> PathBuf {
    let mut h = Sha256::new();
    h.update(appimage.as_bytes());
    let digest = format!("{:x}", h.finalize());
    let ext = if appimage.to_lowercase().ends_with(".svg") { "svg" } else { "png" };
    let _ = std::fs::create_dir_all(cache_base);
    cache_base.join(format!("{}.{}", &digest[..24], ext))
}

/// E133 — AS RAÍZES DOS CACHES DE JOGO (a ordem do dono: Lutris,
/// Heroic, Hydra e Steam): onde cada loja/launcher GUARDA os ícones e
/// capas que já baixou — o botão do .exe reaproveita antes de extrair
/// coisa alguma. Raízes inexistentes são descartadas pelo chamador
/// (busca barata, sem stat por candidato).
pub fn game_cache_roots(home: &Path) -> Vec<PathBuf> {
    vec![
        // Steam: os .ico oficiais por appid e o cache da biblioteca
        home.join(".local/share/Steam/steam/games"),
        home.join(".local/share/Steam/appcache/librarycache"),
        // Lutris: banners/capas baixados dos serviços
        home.join(".cache/lutris"),
        home.join(".local/share/lutris"),
        // Heroic: os assets das bibliotecas conectadas
        home.join(".config/heroic"),
        home.join(".cache/heroic"),
        // Hydra: o launcher do dono (1.0-105 — o DIR DE CONFIG entra
        // na rede: o Hydra guarda capas/ícones em ~/.config/hydra
        // também — a varredura veste o que a loja já baixou)
        home.join(".cache/hydra"),
        home.join(".config/hydra"),
        home.join(".local/share/hydra"),
    ]
}

/// E133 — o caminho CACHEADO do ícone extraído do .exe (Wine/Proton):
/// <cache_base>/<sha256-do-caminho[0..24]>.png — o MESMO formato do
/// appimage-icons (digest truncado em 24; os binários da casa
/// compartilham o desenho). Cria o diretório (a extração depende dele).
pub fn exe_icon_cache_path(cache_base: &Path, exe: &str) -> PathBuf {
    let mut h = Sha256::new();
    h.update(exe.as_bytes());
    let digest = format!("{:x}", h.finalize());
    let _ = std::fs::create_dir_all(cache_base);
    cache_base.join(format!("{}.png", &digest[..24]))
}

// ── E133 — o leitor de PE/ICO: o ícone EMBUTIDO do .exe (Wine/Proton) ──
// O recurso RT_GROUP_ICON (tipo 14) aponta os RT_ICON (tipo 3): o MAIOR
// vence; PNG (muitos modernos) é copiado como está; DIB (BITMAPINFOHEADER
// BGRA/BGR) é convertido para PNG AQUI, std-only — o PNG mínimo com
// blocos zlib STORED é válido, determinístico e não pesa em 48px.

/// CRC32 (IEEE) — o checksum de cada chunk do PNG (std-only, tabela
/// gerada em tempo de build do processo — barato e puro).
fn crc32(data: &[u8]) -> u32 {
    let mut table = [0u32; 256];
    for (i, t) in table.iter_mut().enumerate() {
        let mut c = i as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
        }
        *t = c;
    }
    let mut crc = 0xFFFF_FFFFu32;
    for &b in data {
        crc = table[((crc ^ b as u32) & 0xFF) as usize] ^ (crc >> 8);
    }
    !crc
}

/// Adler32 — o checksum do stream zlib do IDAT (std-only).
fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for &x in data {
        a = (a + x as u32) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

/// O PNG RGBA8 mínimo (std-only): filtro 0 por linha e zlib com blocos
/// STORED (sem compressão — válido em qualquer decoder; o ícone de
/// dock é 48px, os bytes a mais não doem). Puro: bytes INTEIROS em
/// memória, o chamador escreve onde quiser.
pub fn png_rgba_bytes(rgba: &[u8], w: u32, h: u32) -> Option<Vec<u8>> {
    if w == 0 || h == 0 || rgba.len() != (w as usize) * (h as usize) * 4 {
        return None;
    }
    let mut raw: Vec<u8> = Vec::with_capacity((w as usize * 4 + 1) * h as usize);
    for y in 0..h as usize {
        raw.push(0u8); // filtro None
        let off = y * w as usize * 4;
        raw.extend_from_slice(&rgba[off..off + w as usize * 4]);
    }
    // zlib: 0x78 0x01 (sem dicionário, o mais lento/mais simples) +
    // blocos STORED de até 65535 bytes + adler32 do ORIGINAL
    // (chunks — NÃO chunks_exact: o bloco final parcial é ícone também)
    let mut idat: Vec<u8> = vec![0x78, 0x01];
    let n = raw.len();
    if n == 0 {
        return None;
    }
    let nblocks = n.div_ceil(65535);
    for (i, c) in raw.chunks(65535).enumerate() {
        idata_push_stored(&mut idat, i + 1 == nblocks, c);
    }
    idat.extend_from_slice(&adler32(&raw).to_be_bytes());
    let mut out: Vec<u8> = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
    let mut ihdr: Vec<u8> = Vec::with_capacity(13);
    ihdr.extend_from_slice(&w.to_be_bytes());
    ihdr.extend_from_slice(&h.to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]); // depth 8, RGBA, defl, adam7 off
    push_chunk(&mut out, b"IHDR", &ihdr);
    push_chunk(&mut out, b"IDAT", &idat);
    push_chunk(&mut out, b"IEND", &[]);
    Some(out)
}

fn idata_push_stored(out: &mut Vec<u8>, last: bool, data: &[u8]) {
    out.push(if last { 1 } else { 0 }); // BFINAL + BTYPE=00
    let len = data.len() as u16;
    out.extend_from_slice(&len.to_le_bytes());
    out.extend_from_slice(&(!len).to_le_bytes());
    out.extend_from_slice(data);
}

fn push_chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    let mut body = Vec::with_capacity(4 + data.len());
    body.extend_from_slice(kind);
    body.extend_from_slice(data);
    out.extend_from_slice(&body);
    out.extend_from_slice(&crc32(&body).to_be_bytes());
}

/// O DIB (BITMAPINFOHEADER) de um RT_ICON → RGBA. Suporta BI_RGB 24 e
/// 32bpp, altura bottom-up (positiva — o XOR/AND vem DOBRADO na
/// altura) e top-down (negativa); a máscara AND de 1bpp que segue o
/// XOR é IGNORADA (o 32bpp já carrega alpha; no 24bpp o alpha nasce
/// 255 — ícone é quadrado cheio, o recorte é do tema escuro da dock).
pub fn dib_to_rgba(dib: &[u8]) -> Option<(Vec<u8>, u32, u32)> {
    if dib.len() < 40 {
        return None;
    }
    let _bi_size = rd_u32_at(dib, 0)?;
    let w = i32::from_le_bytes(dib[4..8].try_into().ok()?);
    let h_raw = i32::from_le_bytes(dib[8..12].try_into().ok()?);
    let _planes = rd_u16_at(dib, 12)?;
    let bpp = rd_u16_at(dib, 14)? as u32;
    let compression = rd_u32_at(dib, 16)?;
    if compression != 0 || (bpp != 24 && bpp != 32) || w <= 0 || h_raw == 0 {
        return None;
    }
    let top_down = h_raw < 0;
    let h = (h_raw.unsigned_abs() / 2).max(1);
    let w = w as u32;
    let row = (bpp as usize * w as usize).div_ceil(32) * 4;
    let need = 40 + row * h as usize;
    if dib.len() < need {
        return None;
    }
    let mut out = vec![0u8; (w * h * 4) as usize];
    for y in 0..h as usize {
        let src_y = if top_down { y } else { h as usize - 1 - y };
        let line = &dib[40 + src_y * row..40 + src_y * row + row];
        for x in 0..w as usize {
            let (b, g, r, a) = match bpp {
                32 => (line[x * 4], line[x * 4 + 1], line[x * 4 + 2], line[x * 4 + 3]),
                _ => (line[x * 3], line[x * 3 + 1], line[x * 3 + 2], 0xFF),
            };
            let o = (y * w as usize + x) * 4;
            out[o] = r;
            out[o + 1] = g;
            out[o + 2] = b;
            out[o + 3] = a;
        }
    }
    Some((out, w, h))
}

fn rd_u16_at(b: &[u8], o: usize) -> Option<u16> {
    Some(u16::from_le_bytes(b.get(o..o + 2)?.try_into().ok()?))
}

fn rd_u32_at(b: &[u8], o: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(o..o + 4)?.try_into().ok()?))
}

/// As entradas de um diretório de recurso: (NameOrId, OffsetToData)
/// com os bits altos já interpretados (is_dir, offset relativo à base
/// do recurso).
fn res_entries(b: &[u8], base: usize, off: usize) -> Option<Vec<(u32, bool, usize)>> {
    let dir = base + off;
    let named = rd_u16_at(b, dir + 12)? as usize;
    let ids = rd_u16_at(b, dir + 14)? as usize;
    let mut out = Vec::new();
    for i in 0..(named + ids) {
        let e = dir + 16 + i * 8;
        let name = rd_u32_at(b, e)?;
        let val = rd_u32_at(b, e + 4)?;
        // nome STRING (bit alto): o ID puro é o caminho da casa — pula
        // a entrada sem morte (ícone por nome é raro e jamais da casa)
        if name & 0x8000_0000 != 0 {
            continue;
        }
        let is_dir = val & 0x8000_0000 != 0;
        let rel = (val & 0x7FFF_FFFF) as usize;
        out.push((name, is_dir, rel));
    }
    Some(out)
}

/// A folha de dados de um recurso: (offset NO ARQUIVO, tamanho).
fn res_data(b: &[u8], base: usize, sections: &[(u32, u32, u32, u32)], leaf_rel: usize) -> Option<(usize, usize)> {
    let e = base + leaf_rel;
    let rva = rd_u32_at(b, e)?;
    let size = rd_u32_at(b, e + 4)? as usize;
    let off = rva_to_off(sections, rva)?;
    Some((off, size))
}

/// RVA → offset de arquivo pela tabela de seções
/// ((virt_addr, virt_size, raw_size, raw_ptr)).
fn rva_to_off(sections: &[(u32, u32, u32, u32)], rva: u32) -> Option<usize> {
    for &(va, vsz, rsz, ptr) in sections {
        let sz = vsz.max(rsz);
        if rva >= va && rva < va + sz {
            return Some((ptr + (rva - va)) as usize);
        }
    }
    None
}

/// E133 — o ícone EMBUTIDO de um .exe em BYTES PNG (a função PURA —
/// `extract_pe_icon` é a casca que lê o arquivo e escreve o destino).
/// O caminho: DOS 'MZ' → PE → data dir de RECURSO (índice 2) →
/// RT_GROUP_ICON (tipo 14, o maior pelo GRPICONDIRENTRY) → RT_ICON
/// (tipo 3, id apontado) → PNG como está ou DIB→PNG. PE sem grupo
/// tenta o RT_ICON direto. None em tudo que não é PE/sem ícone —
/// a casa NUNCA adivinha ícone.
pub fn extract_pe_icon_bytes(b: &[u8]) -> Option<Vec<u8>> {
    if b.len() < 0x40 || &b[0..2] != b"MZ" {
        return None;
    }
    let lfanew = rd_u32_at(b, 0x3C)? as usize;
    if b.get(lfanew..lfanew + 4) != Some(b"PE\0\0") {
        return None;
    }
    let coff = lfanew + 4;
    let nsec = rd_u16_at(b, coff + 2)? as usize;
    let size_opt = rd_u16_at(b, coff + 16)? as usize;
    let opt = coff + 20;
    let magic = rd_u16_at(b, opt)?;
    let dd = match magic {
        0x10B => opt + 96, // PE32
        0x20B => opt + 112, // PE32+
        _ => return None,
    };
    let rsrc_rva = rd_u32_at(b, dd + 16)?; // data dir [2] = RECURSO
    if rsrc_rva == 0 {
        return None;
    }
    let mut sections: Vec<(u32, u32, u32, u32)> = Vec::new();
    for i in 0..nsec {
        let s = opt + size_opt + i * 40;
        let vsz = rd_u32_at(b, s + 8)?;
        let va = rd_u32_at(b, s + 12)?;
        let rsz = rd_u32_at(b, s + 16)?;
        let ptr = rd_u32_at(b, s + 20)?;
        sections.push((va, vsz, rsz, ptr));
    }
    let base = rva_to_off(&sections, rsrc_rva)?;

    // L1: o tipo. RT_GROUP_ICON=14 primeiro; sem grupo, RT_ICON=3.
    let l1 = res_entries(b, base, 0)?;
    let find_dir = |t: u32| -> Option<usize> {
        l1.iter().find(|(id, is_dir, _)| *id == t && *is_dir).map(|(_, _, rel)| *rel)
    };
    let read_icon = |l2_rel: usize| -> Option<Vec<u8>> {
        let l2 = res_entries(b, base, l2_rel)?;
        let (_, _, l3_rel) = l2.iter().find(|(_, is_dir, _)| *is_dir)?;
        let l3 = res_entries(b, base, *l3_rel)?;
        let leaf = l3
            .iter()
            .find(|(_, is_dir, _)| !*is_dir)
            .map(|(_, _, leaf)| *leaf)?;
        let (off, size) = res_data(b, base, &sections, leaf)?;
        b.get(off..off + size).map(|s| s.to_vec())
    };
    // o grupo: o MAIOR ícone das entradas (width*height, bitcount
    // desempata); cada GRPICONDIRENTRY aponta o id do RT_ICON
    if let Some(g_rel) = find_dir(14) {
        let grp_raw = read_icon(g_rel)?;
        if grp_raw.len() >= 6 {
            let count = u16::from_le_bytes([grp_raw[4], grp_raw[5]]) as usize;
            let mut best: Option<(u32, u16)> = None;
            for i in 0..count {
                let e = 6 + i * 14;
                if e + 14 > grp_raw.len() {
                    break;
                }
                let w = grp_raw[e] as u32;
                let h = grp_raw[e + 1] as u32;
                let bc = u16::from_le_bytes([grp_raw[e + 6], grp_raw[e + 7]]) as u32;
                let nid = u16::from_le_bytes([grp_raw[e + 12], grp_raw[e + 13]]);
                let score = (if w == 0 { 256 } else { w }) * (if h == 0 { 256 } else { h }) * (bc.max(1));
                if best.as_ref().map(|(s, _)| score > *s).unwrap_or(true) {
                    best = Some((score, nid));
                }
            }
            if let Some((_, nid)) = best {
                // o RT_ICON com o ID apontado pelo grupo
                if let Some(i_rel) = find_dir(3) {
                    let l2 = res_entries(b, base, i_rel)?;
                    for (id, is_dir, l3_rel) in l2 {
                        if !is_dir || id != nid as u32 {
                            continue;
                        }
                        let l3 = res_entries(b, base, l3_rel)?;
                        for (_, d2, leaf) in l3 {
                            if d2 {
                                continue;
                            }
                            if let Some((off, size)) = res_data(b, base, &sections, leaf) {
                                if let Some(png) = icon_bytes_to_png(&b[off..off + size]) {
                                    return Some(png);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // sem grupo (ou grupo quebrado): o PRIMEIRO RT_ICON direto
    if let Some(i_rel) = find_dir(3) {
        if let Some(raw) = read_icon(i_rel) {
            return icon_bytes_to_png(&raw);
        }
    }
    None
}

/// PNG como está; DIB → PNG (a conversão std-only da casa).
fn icon_bytes_to_png(raw: &[u8]) -> Option<Vec<u8>> {
    if raw.starts_with(&[0x89, b'P', b'N', b'G']) {
        return Some(raw.to_vec());
    }
    let (rgba, w, h) = dib_to_rgba(raw)?;
    png_rgba_bytes(&rgba, w, h)
}

/// E133 — a CASCA de arquivo do extrator: lê o .exe, extrai o ícone
/// em PNG e escreve no destino (criando o diretório). Devolve o
/// destino ou None (o chamador decide o próximo degrau da cadeia).
pub fn extract_pe_icon(exe: &Path, dest: &Path) -> Option<PathBuf> {
    let b = std::fs::read(exe).ok()?;
    let png = extract_pe_icon_bytes(&b)?;
    if let Some(parent) = dest.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    std::fs::write(dest, png).ok()?;
    Some(dest.to_path_buf())
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
/// exports do Flatpak) NO MODO LIMPO: NoDisplay/Hidden NUNCA entram (a
/// lei E21 da gaveta, herdada: helper rodando não é app de dock). A
/// dock veste a COMPLETA (`scan_desktop_dir_todos` — 1.0-104, a
/// identidade dos jogos NoDisplay); a LIMPA é o CONTRATO DOS TESTES (a
/// prova viva de que a lei E21 continua na varredura da casa — o
/// consumidor de GUI é a completa, o de gaveta é o nwg-drawer FORA daqui).
#[cfg(test)]
pub fn scan_desktop_dir(dir: &Path) -> Vec<DesktopEntry> {
    varre_desktops(dir, false)
}

/// 1.0-104 — A VARREDURA COMPLETA (com NoDisplay/Hidden) para a
/// IDENTIDADE da dock (a lei E21 é da GAVETA, não da dock: o jogo
/// Steam/Hydra deixa o .desktop com NoDisplay=true em
/// ~/.local/share/applications — o steam_app_413150.desktop do
/// Stardew Valley — e o índice da dock precisa dele para casar a
/// JANELA aberta pelo app_id e vestir o ÍCONE de verdade; a gaveta
/// (nwg-drawer) continua com a varredura LIMPA — quem é NoDisplay não
/// é app de LANÇAR, mas é identidade de MOSTRAR).
/// (Consumidor único: a montagem da dock na gui — como o `desktop_dirs`
/// ao lado, o allow do stub sem-gui é a mesma escola; o teste é o
/// outro consumidor do núcleo puro.)
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn scan_desktop_dir_todos(dir: &Path) -> Vec<DesktopEntry> {
    varre_desktops(dir, true)
}

fn varre_desktops(dir: &Path, incluir_ocultos: bool) -> Vec<DesktopEntry> {
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
        if !incluir_ocultos && (e.no_display || e.hidden) {
            continue;
        }
        out.push(e);
    }
    out
}

/// Os diretórios de .desktop que a casa varre (E132 — os EXPORTS do
/// Flatpak ANTES do sistema: o Flatpak instalado pelo usuário mora no
/// export dele, não em /usr/share/applications).
/// (Consumidor único: a montagem da dock na gui — no núcleo sem gui a
/// função descansa, a voz abaixo mantém a casa sem aviso nenhum.)
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn desktop_dirs(home: &Path) -> Vec<PathBuf> {
    vec![
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        home.join(".local/share/flatpak/exports/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
        PathBuf::from("/usr/share/applications"),
        home.join(".local/share/applications"),
    ]
}

/// E106/3 — O .desktop AUXILIAR não é app de identidade: os nomes que
/// o ambiente Xfce/thunar deixa ao lado do dono (`thunar-bulk-rename`,
/// os `*-settings`, a família `exo-*`) carregam o MESMO StartupWMClass
/// do app de verdade — indexá-los rouba a chave do dono (o rig provou:
/// clicar no botão do gerenciador de arquivos abria "Renomear em massa"
/// porque o bulk-rename, que ordena ANTES no alfabeto, registrava
/// "thunar" primeiro). O auxiliar só veste a PRÓPRIA identidade (o
/// stem do id dele) no índice — o jogo steam_app_* NoDisplay NÃO é
/// auxiliar e segue indexado inteiro (a identidade dos jogos é a lei
/// 1.0-104, intocada).
pub fn desktop_eh_auxiliar(e: &DesktopEntry) -> bool {
    let id = fold(e.id.trim_end_matches(".desktop"));
    if id.starts_with("exo-") {
        return true;
    }
    if id.ends_with("-bulk-rename") || id.ends_with("-settings") {
        return true;
    }
    // o Exec claramente auxiliar (o exo-* que o item de menu carrega)
    first_binary(&strip_field_codes(&e.exec))
        .map(|b| b.to_lowercase().starts_with("exo-"))
        .unwrap_or(false)
}

/// E132 — o ÍNDICE de .desktops: chave (fold) → entrada. As chaves de
/// cada entrada: StartupWMClass, o 1º binário do Exec, o id sem o
/// .desktop E as alternativas REVERSE-DNS ("bazaar" para o
/// io.github.kolunmi.Bazaar.desktop — a ordem do dono). A PRIMEIRA
/// chave vence (setdefault do Python), com DUAS leis E106/3 por cima:
///   · o AUXILIAR só veste o próprio id (o StartupWMClass/binário dele
///     nunca roubam a chave do dono — thunar.desktop vence para Thunar);
///   · o OCULTO (NoDisplay/Hidden) nunca rouba a chave do VISÍVEL: o
///     foot-server.desktop NoDisplay da casa carrega Exec=foot --server
///     e a chave "foot" era DELE (o /usr/local ordena antes do
///     /usr/share) — o clique no comm "foot" lançava o DAEMON do
///     terminal em vez do terminal. O visível desocupa o oculto; entre
///     iguais, a primeira continua vencendo (o steam_app_* NoDisplay
///     segue dono das chaves DELE — ninguém visível as quer).
pub fn desktop_index(entries: &[DesktopEntry]) -> HashMap<String, usize> {
    let mut idx: HashMap<String, usize> = HashMap::new();
    let oculto = |e: &DesktopEntry| e.no_display || e.hidden;
    for (i, e) in entries.iter().enumerate() {
        let mut keys: Vec<String> = Vec::new();
        // E106/3 — o auxiliar só assina o PRÓPRIO nome (o stem do id)
        if !desktop_eh_auxiliar(e) {
            if !e.wm_class.is_empty() {
                keys.push(fold(&e.wm_class));
            }
            let bin = first_binary(&strip_field_codes(&e.exec));
            if let Some(b) = bin {
                keys.push(fold(&b));
            }
        }
        keys.extend(reverse_dns_alternates(&e.id).iter().map(|k| fold(k)));
        for k in keys {
            if k.is_empty() {
                continue;
            }
            match idx.get(&k) {
                // vaga livre: a primeira lei de sempre
                None => {
                    idx.insert(k, i);
                }
                // o dono atual é OCULTO e o novo é VISÍVEL: desocupa
                Some(&j) if oculto(&entries[j]) && !oculto(e) => {
                    idx.insert(k, i);
                }
                // em todo o resto a PRIMEIRA chave segue vencendo
                _ => {}
            }
        }
    }
    idx
}

/// 1.0-104 — O ÍNDICE POR NOME (a rede do título da janela: o fold do
/// Name do .desktop → entrada — o "Stardew Valley" da janela casa o
/// "Stardew Valley" do .desktop que nenhum app_id nomeia; a PRIMEIRA
/// chave vence, a mesma lei do índice de comm).
/// (Consumidor único: a montagem da dock na gui — o allow do stub
/// sem-gui é a escola do `desktop_dirs`; o teste é o outro consumidor.)
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn name_index(entries: &[DesktopEntry]) -> HashMap<String, usize> {
    let mut idx: HashMap<String, usize> = HashMap::new();
    for (i, e) in entries.iter().enumerate() {
        if e.name.is_empty() {
            continue;
        }
        idx.entry(fold(&e.name)).or_insert(i);
    }
    idx
}

/// 1.0-104 — A RESOLUÇÃO PELO TÍTULO DA JANELA (o juízo EXATO do fold:
/// o título inteiro normalizado casa o Name inteiro normalizado — sem
/// contenção, o título "Stardew Valley — Notificações" NÃO é o jogo;
/// a janela de jogo tem o título DO JOGO). None = o título não é nome
/// de nenhum app conhecido.
/// (Consumidor único: a montagem da dock na gui — o allow do stub
/// sem-gui é a escola do `desktop_dirs`; o teste é o outro consumidor.)
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn resolve_por_titulo<'a>(
    idx: &HashMap<String, usize>,
    entries: &'a [DesktopEntry],
    titulo: &str,
) -> Option<&'a DesktopEntry> {
    let t = fold(titulo);
    if t.is_empty() {
        return None;
    }
    idx.get(&t).map(|i| &entries[*i])
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

/// E139 — A ESCADA DE NORMALIZAÇÃO ÚNICA DO PIN (a auditoria do 1.0-86:
/// o pin "gearlever_Hydra" cujo arquivo real é "gearlever_9f2a_Hydra"
/// era "ignorado (desktop inexistente)" para exibir E para julgar — o
/// MESMO app resolvia por uma via e morria por outra, e o dock.log
/// gritava o pin ignorado a cada arranque). A escada serve EXIBIR e
/// JULGAR com a MESMA régua: quem ela acha, a dock mostra, atualiza no
/// papel e MANTÉM; quem ela NÃO acha em passadas seguidas, morre de
/// verdade (a poda só remove o .desktop que não existe em NENHUM dir
/// XDG — nunca uma variação de caixa ou de prefixo). Degraus:
///   1. o fold do id inteiro (o índice inteiro fala fold);
///   2. o stem do id (sem .desktop — e o último segmento do id
///      composto reverse-DNS);
///   3. a CAUDA sem os prefixos de integração (gearlever-/appimage- no
///      espaço do fold) dos DOIS lados: o pin pode ter chegado sem o
///      hash que o Gear Lever assina ("gearlever_Hydra" ↔
///      "gearlever_9f2a_Hydra") ou com ele quando o papel não tem;
///   4. contenção com fronteira (near_match — 'brave' ⊂ 'brave-browser'
///      casa; 'foot' ⊂ 'footclient' NÃO — a lei v2.10.6 intocada).
pub fn resolve_pin<'a>(
    idx: &HashMap<String, usize>,
    entries: &'a [DesktopEntry],
    id: &str,
) -> Option<&'a DesktopEntry> {
    let c = id.trim();
    if c.is_empty() {
        return None;
    }
    // (1) o fold do id inteiro
    let f = fold(c);
    if let Some(i) = idx.get(&f) {
        return Some(&entries[*i]);
    }
    // (2) o stem: sem .desktop e o último segmento do id composto
    let sem = f.strip_suffix(".desktop").unwrap_or(&f).to_string();
    if let Some(i) = idx.get(&sem) {
        return Some(&entries[*i]);
    }
    if let Some(ultimo) = sem.rsplit('.').next() {
        if let Some(i) = idx.get(ultimo) {
            return Some(&entries[*i]);
        }
    }
    // (3) a cauda sem os prefixos de integração — os DOIS lados. O fold
    //     já trocou '_' por '-' e baixou a caixa: os prefixos vivem no
    //     espaço do fold ("gearlever-9f2a-hydra").
    fn cauda(s: &str) -> &str {
        for pref in ["gearlever-", "appimage-"] {
            if let Some(r) = s.strip_prefix(pref) {
                return r;
            }
        }
        s
    }
    let agulha = cauda(&sem);
    if let Some(i) = idx.get(agulha) {
        return Some(&entries[*i]);
    }
    for (k, i) in idx {
        if crate::sock::near_match(agulha, cauda(k)) {
            return Some(&entries[*i]);
        }
    }
    // (4) contenção com fronteira (a gramática do resolve_desktop)
    for (k, i) in idx {
        if crate::sock::near_match(&sem, k) {
            return Some(&entries[*i]);
        }
    }
    None
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
            if chars.peek().is_some_and(|n| n.is_ascii_alphabetic()) {
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

/// O 1º binário do commandline (shlex do Python: aqui, um split simples
/// por espaço — os Exec da casa não citam o 1º token). E106/5 — o token
/// CITADO é o binário inteiro: o .desktop LOCAL gerado pela fixação do
/// sem-nome cita o caminho com espaço (Exec="/opt/Apps/Hydra
/// Plus.AppImage") e o split cru partiria a citação no meio.
pub fn first_binary(raw: &str) -> Option<String> {
    let s = raw.trim();
    let tok = if s.starts_with('"') {
        // entre aspas: o caminho com espaço é UM token só
        s.split('"').nth(1).filter(|t| !t.is_empty())?
    } else if s.starts_with('\'') {
        s.split('\'').nth(1).filter(|t| !t.is_empty())?
    } else {
        s.split_whitespace().next()?
    };
    Some(Path::new(tok).file_name()?.to_string_lossy().into_owned())
}

// ── a chave do botão RAW (E106 — a denylist dos diálogos de daemon) ──

/// E106 — janela de DAEMON/diálogo de sistema não é aplicativo: o
/// diálogo do chaveiro (gcr-prompter), os agentes polkit, o zenity e
/// o OSD NUNCA ganham botão na dock (a mesa é de PROGRAMAS).
/// 1.0-105 — O SERVIDOR/CLIENTE DO TERMINAL idem (a ordem do dono: o
/// foot-server é o daemon do foot (nunca janela de app) e o footclient
/// é a PONTE do cliente (a janela é do foot de sempre — o client só
/// poluiria os ícones abertos com o glifo genérico da ponte).
pub const RAW_DENY_STEMS: [&str; 8] = [
    "gcr-prompter",
    "lxqt-policykit",
    "polkit-gnome",
    "zenity",
    "swayosd",
    "hyprpolkitagent",
    "foot-server",
    "footclient",
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

// ── E106/5 — o .desktop LOCAL do sem-nome (a fixação que gera endereço) ──

/// E106/5 — o ID do .desktop LOCAL do sem-nome: `elite-<chave>.desktop`
/// em ~/.local/share/applications (o papel é do DONO, nunca do sistema).
/// A chave veste o fold da casa e o que não é letra/número vira traço
/// (nome de ARQUIVO não carrega espaço; o StartupWMClass lá dentro
/// segue com a chave CRUA para casar a janela na gramática de sempre).
pub fn elite_desktop_id(key: &str) -> String {
    let limpo: String = fold(key)
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '-' { c } else { '-' })
        .collect();
    format!("elite-{limpo}.desktop")
}

/// E106/5 — o CORPO do .desktop do sem-nome (puro, testado): Name = o
/// nome do botão, Exec = a PROVA de origem que o botão raw usa no
/// "Nova janela" (argv[0]/AppImage do /proc — o caminho com espaço veste
/// aspas, a spec manda e o sh da casa entende), StartupWMClass = a
/// chave crua (a janela casa na hora), Terminal=false e NoDisplay=false
/// (o dono QUER ver o que fixou). Icon só quando há caminho resolvido
/// em disco — sem ícone, o campo OMITE (nunca glifo mentiroso).
pub fn desktop_do_raw(key: &str, name: &str, exec: &str, icon: Option<&Path>) -> String {
    let mut out = String::new();
    out.push_str("# elite-dock: gerado pela dock (E106) — o sem-nome ganhou endereço\n");
    out.push_str("[Desktop Entry]\n");
    out.push_str("Type=Application\n");
    out.push_str(&format!("Name={name}\n"));
    if exec.contains(' ') {
        out.push_str(&format!("Exec=\"{exec}\"\n"));
    } else {
        out.push_str(&format!("Exec={exec}\n"));
    }
    if let Some(p) = icon {
        out.push_str(&format!("Icon={}\n", p.display()));
    }
    out.push_str(&format!("StartupWMClass={key}\n"));
    out.push_str("Terminal=false\n");
    out.push_str("NoDisplay=false\n");
    out
}

/// E106/5 — o .desktop é DA CASA? A assinatura da primeira linha é o
/// contrato: o desafixar só APAGA o arquivo que a própria dock gerou —
/// o .desktop do dono, colocado à mão com o mesmo nome, fica (o papel
/// é dele).
pub fn eh_desktop_da_casa(txt: &str) -> bool {
    txt.trim_start().starts_with("# elite-dock:")
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
        let hit = find_icon_file("bazaar", std::slice::from_ref(&root));
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
        // 1.0-105 — o SERVIDOR/CLIENTE do terminal idem (a ponte nunca
        // é app; o FOOT de sempre segue botão de primeira classe)
        assert!(raw_key("foot-server", "foot-server").is_none());
        assert!(raw_key("footclient", "footclient").is_none());
        assert!(raw_key("foot", "foot").is_some());
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

    // ── E133 — os helpers de arquivo dos testes do extrator PE ────────

    fn poke16(v: &mut [u8], off: usize, x: u16) {
        v[off..off + 2].copy_from_slice(&x.to_le_bytes());
    }
    fn poke32(v: &mut [u8], off: usize, x: u32) {
        v[off..off + 4].copy_from_slice(&x.to_le_bytes());
    }

    /// Um diretório de recurso: cabeçalho de 16 bytes + entradas de ID
    /// (name, val) — o FLAG de subdiretório já vem no val do chamador.
    fn res_dir(v: &mut [u8], off: usize, entries: &[(u32, u32)]) {
        poke16(v, off + 12, 0);
        poke16(v, off + 14, entries.len() as u16);
        for (i, (name, val)) in entries.iter().enumerate() {
            let e = off + 16 + i * 8;
            poke32(v, e, *name);
            poke32(v, e + 4, *val);
        }
    }

    /// Um .exe de MENTIRA com o recurso de ícone de verdade (a mesma
    /// anatomia do PE real: seção .rsrc com RT_GROUP_ICON apontando o
    /// RT_ICON — o molde do teste prova o extrator SEM binário de jogo).
    fn build_test_pe(icon: &[u8]) -> Vec<u8> {
        const FLAG: u32 = 0x8000_0000;
        const RSRC_RVA: u32 = 0x1000;
        const RAW_PTR: usize = 0x200;
        // ── a seção de recurso (tudo relativo à base) ──
        let mut r = vec![0u8; 0x500];
        res_dir(&mut r, 0x000, &[(3, 0x100 | FLAG), (14, 0x200 | FLAG)]); // L1: tipos
        res_dir(&mut r, 0x100, &[(1, 0x110 | FLAG)]); // RT_ICON: nome 1
        res_dir(&mut r, 0x110, &[(0x409, 0x140)]); // língua → folha
        poke32(&mut r, 0x140, RSRC_RVA + 0x300); // data entry do ícone
        poke32(&mut r, 0x144, icon.len() as u32);
        res_dir(&mut r, 0x200, &[(1, 0x210 | FLAG)]); // RT_GROUP_ICON: nome 1
        res_dir(&mut r, 0x210, &[(0x409, 0x240)]);
        poke32(&mut r, 0x240, RSRC_RVA + 0x400); // data entry do grupo
        poke32(&mut r, 0x244, 20u32);
        r[0x300..0x300 + icon.len()].copy_from_slice(icon);
        // GRPICONDIR: reserved, type=1, count=1 + GRPICONDIRENTRY(14)
        poke16(&mut r, 0x400, 0);
        poke16(&mut r, 0x402, 1);
        poke16(&mut r, 0x404, 1);
        r[0x406] = 8; // bWidth
        r[0x407] = 8; // bHeight
        r[0x408] = 0; // bColorCount
        r[0x409] = 0; // bReserved
        poke16(&mut r, 0x40A, 1); // wPlanes
        poke16(&mut r, 0x40C, 32); // wBitCount
        poke32(&mut r, 0x40E, icon.len() as u32); // dwBytesInRes
        poke16(&mut r, 0x412, 1); // nID → o RT_ICON de nome 1

        // ── o esqueleto PE em volta ──
        let mut pe = vec![0u8; RAW_PTR + r.len()];
        pe[0..2].copy_from_slice(b"MZ");
        poke32(&mut pe, 0x3C, 0x40); // e_lfanew
        pe[0x40..0x44].copy_from_slice(b"PE\0\0");
        let coff = 0x44;
        poke16(&mut pe, coff + 2, 1); // 1 seção
        poke16(&mut pe, coff + 16, 224); // optional header (PE32+16 dirs)
        let opt = 0x58; // coff + 20
        poke16(&mut pe, opt, 0x10B); // magic PE32
        poke32(&mut pe, opt + 96 + 16, RSRC_RVA); // data dir [2] RECURSO
        poke32(&mut pe, opt + 96 + 20, r.len() as u32);
        let sh = opt + 224;
        pe[sh..sh + 5].copy_from_slice(b".rsrc");
        poke32(&mut pe, sh + 8, r.len() as u32); // VirtualSize
        poke32(&mut pe, sh + 12, RSRC_RVA); // VirtualAddress
        poke32(&mut pe, sh + 16, r.len() as u32); // SizeOfRawData
        poke32(&mut pe, sh + 20, RAW_PTR as u32); // PointerToRawData
        pe[RAW_PTR..RAW_PTR + r.len()].copy_from_slice(&r);
        pe
    }

    /// Um DIB (BITMAPINFOHEADER BGRA) 2x2 bottom-up para o extrator.
    fn build_test_dib() -> Vec<u8> {
        let mut d = vec![0u8; 40 + 8 * 2];
        poke32(&mut d, 0, 40); // biSize
        poke32(&mut d, 4, 2); // biWidth
        poke32(&mut d, 8, 4); // biHeight DOBRADO (XOR 2 + AND 2)
        poke16(&mut d, 12, 1); // planes
        poke16(&mut d, 14, 32); // 32bpp
        poke32(&mut d, 16, 0); // BI_RGB
        // linha 0 armazenada = LINHA DE BAIXO do ícone (bottom-up):
        // (x=0,y=1)=B=0,G=1,R=128,A=255 · (x=1,y=1)=B=1,G=1,R=128,A=255
        d[40..44].copy_from_slice(&[0, 1, 128, 255]);
        d[44..48].copy_from_slice(&[1, 1, 128, 255]);
        // linha 1 armazenada = linha de CIMA: (0,0) e (1,0)
        d[48..52].copy_from_slice(&[0, 0, 128, 255]);
        d[52..56].copy_from_slice(&[1, 0, 128, 255]);
        d
    }

    #[test]
    fn e133_png_minimo_e_crc32_pelos_vetores() {
        // crc32 IEEE do vetor clássico "123456789" = 0xCBF43926
        let mut table = [0u32; 256];
        for (i, t) in table.iter_mut().enumerate() {
            let mut c = i as u32;
            for _ in 0..8 {
                c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
            }
            *t = c;
        }
        // (o teste re-prova a tabela porque o crc32 é privado; o VETOR
        // é o juiz de verdade: 0x CBF4 3926)
        let mut c = 0xFFFF_FFFFu32;
        for &b in b"123456789" {
            c = table[((c ^ b as u32) & 0xFF) as usize] ^ (c >> 8);
        }
        assert_eq!(!c, 0xCBF4_3926);
        // o PNG mínimo: assinatura + IHDR com as dimensões + IEND
        let px = vec![255u8, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255];
        let png = png_rgba_bytes(&px, 2, 2).unwrap();
        assert_eq!(&png[0..8], &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
        // IHDR: len 13 + tipo + w,h BE + depth 8/RGBA
        assert_eq!(&png[8..12], &13u32.to_be_bytes());
        assert_eq!(&png[12..16], b"IHDR");
        assert_eq!(&png[16..20], &2u32.to_be_bytes());
        assert_eq!(&png[20..24], &2u32.to_be_bytes());
        assert_eq!(&png[24..29], &[8, 6, 0, 0, 0]);
        // termina em IEND
        assert_eq!(&png[png.len() - 8..png.len() - 4], b"IEND");
        // o IDAT decodifica como raw: 2 linhas × (filtro 0 + 2×RGBA)
        assert_eq!(png[41], 0x78); // zlib CMF
        assert_eq!(png[42], 0x01); // FLG (stored)
        // dimensões erradas: None (a casa não fabrica PNG torto)
        assert!(png_rgba_bytes(&px, 3, 2).is_none());
        assert!(png_rgba_bytes(&px, 0, 2).is_none());
    }

    #[test]
    fn e133_dib_32bpp_bottom_up_vira_rgba() {
        let (rgba, w, h) = dib_to_rgba(&build_test_dib()).unwrap();
        assert_eq!((w, h), (2, 2));
        // topo-esquerda (x=0,y=0): R=128 G=0 B=0 A=255 (a linha de CIMA
        // é a ÚLTIMA armazenada — bottom-up decodificado)
        assert_eq!(&rgba[0..4], &[128, 0, 0, 255]);
        // baixo-direita (x=1,y=1): B=1,G=1 → RGBA [128,1,1,255]
        assert_eq!(&rgba[12..16], &[128, 1, 1, 255]);
        // lixo curto/comprimido: None honesto
        assert!(dib_to_rgba(&[0u8; 10]).is_none());
        let mut comp = build_test_dib();
        poke32(&mut comp, 16, 1); // BI_RLE: não suportado
        assert!(dib_to_rgba(&comp).is_none());
    }

    #[test]
    fn e133_extrator_pe_do_png_embutido() {
        // o ícone PNG embutido volta BYTE A BYTE (sem re-codificação)
        let px = vec![10u8, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255, 100, 110, 120, 255];
        let png = png_rgba_bytes(&px, 2, 2).unwrap();
        let pe = build_test_pe(&png);
        let got = extract_pe_icon_bytes(&pe).unwrap();
        assert_eq!(got, png);
        // não-PE: None honesto (a casa nunca adivinha ícone)
        assert!(extract_pe_icon_bytes(b"MZ lixo sem PE").is_none());
        assert!(extract_pe_icon_bytes(b"#!/bin/sh\n").is_none());
    }

    #[test]
    fn e133_extrator_pe_do_dib_vira_png() {
        let pe = build_test_pe(&build_test_dib());
        let got = extract_pe_icon_bytes(&pe).unwrap();
        assert!(got.starts_with(&[0x89, b'P', b'N', b'G']));
        // o IHDR carrega as dimensões do DIB (2x2)
        assert_eq!(&got[16..20], &2u32.to_be_bytes());
        assert_eq!(&got[20..24], &2u32.to_be_bytes());
    }

    #[test]
    fn e133_extrator_pe_casca_de_arquivo() {
        let root = tmpdir("pefile");
        let png = png_rgba_bytes(&[1u8, 2, 3, 255], 1, 1).unwrap();
        let exe = root.join("Jogo.exe");
        std::fs::write(&exe, build_test_pe(&png)).unwrap();
        let dest = root.join("cache/abc.png");
        let got = extract_pe_icon(&exe, &dest).unwrap();
        assert_eq!(got, dest);
        assert_eq!(std::fs::read(&dest).unwrap(), png);
        // exe inexistente: None (a thread da UI segue para o próximo degrau)
        assert!(extract_pe_icon(&root.join("nao-tem.exe"), &dest).is_none());
    }

    #[test]
    fn e133_cache_do_exe_e_as_raizes_de_jogo() {
        // o mesmo formato do appimage: sha256-do-caminho[0..24] + .png
        let cache = tmpdir("execache");
        let p = exe_icon_cache_path(&cache, "/opt/games/Stardew Valley.exe");
        assert!(p.extension().and_then(|e| e.to_str()) == Some("png"));
        assert_eq!(p.file_name().unwrap().to_string_lossy().len(), 28); // 24 + '.png'
        // DETERMINÍSTICO: o mesmo caminho, o mesmo nome
        assert_eq!(p, exe_icon_cache_path(&cache, "/opt/games/Stardew Valley.exe"));
        assert_ne!(p, exe_icon_cache_path(&cache, "/opt/games/Outro.exe"));
        // as raízes da ordem do dono: Steam, Lutris, Heroic e Hydra
        let home = PathBuf::from("/home/dono");
        let roots = game_cache_roots(&home);
        assert!(roots.contains(&home.join(".local/share/Steam/steam/games")));
        assert!(roots.contains(&home.join(".local/share/Steam/appcache/librarycache")));
        assert!(roots.contains(&home.join(".cache/lutris")));
        assert!(roots.contains(&home.join(".config/heroic")));
        assert!(roots.contains(&home.join(".cache/hydra")));
        // 1.0-105 — o DIR DE CONFIG do Hydra também (as capas/ícones do
        // launcher moram em ~/.config/hydra — a rede cobre os dois)
        assert!(roots.contains(&home.join(".config/hydra")));
    }

    #[test]
    fn e133_find_image_file_casa_o_ico_do_steam() {
        let root = tmpdir("gamecache");
        let games = root.join("steam/games");
        std::fs::create_dir_all(&games).unwrap();
        // o cache do Steam guarda <appid>/icon.ico e capsule jpgs
        std::fs::write(games.join("413150.ico"), b"ico").unwrap();
        std::fs::write(root.join("steam/capsule_231.jpg"), b"jpg").unwrap();
        // a lista AMPLA casa .ico/.jpg que a ICON_EXTS recusaria
        assert_eq!(
            find_image_file("413150", &[root.join("steam/games")]),
            Some(games.join("413150.ico"))
        );
        assert_eq!(
            find_image_file("capsule_231", &[root.join("steam")]),
            Some(root.join("steam/capsule_231.jpg"))
        );
        // a lista RESTRITA segue recusando .ico (a busca de TEMA é png/svg)
        assert!(find_icon_file("413150", &[root.join("steam/games")]).is_none());
        // fold: 'Stardew Valley' acha 'StardewValley.ico'
        std::fs::write(games.join("StardewValley.ico"), b"ico2").unwrap();
        assert_eq!(
            find_image_file("Stardew Valley", &[root.join("steam/games")]),
            Some(games.join("StardewValley.ico"))
        );
    }

    /// E139 — a escada do pin: o juízo ÚNICO de exibir e podar.
    fn indice_de_mentira(ids: &[&str]) -> (Vec<DesktopEntry>, HashMap<String, usize>) {
        let entries: Vec<DesktopEntry> = ids
            .iter()
            .map(|id| DesktopEntry {
                id: (*id).to_string(),
                ..Default::default()
            })
            .collect();
        let idx = desktop_index(&entries);
        (entries, idx)
    }

    #[test]
    fn e139_a_escada_do_pin_resolve_as_variantes_que_o_app_real_tem() {
        // O CASO DO DONO (auditoria do 1.0-86): o Gear Lever assina o
        // arquivo com hash (gearlever_9f2a_Hydra.desktop) e o pin pode
        // ter chegado SEM ele (gearlever_Hydra) — ou com CAIXA variada.
        let (entries, idx) = indice_de_mentira(&["gearlever_9f2a_Hydra.desktop", "foot.desktop"]);
        // a variação de PREFIXO e de CAIXA resolve — nunca é "morto"
        let hit = resolve_pin(&idx, &entries, "gearlever_Hydra");
        assert!(hit.is_some(), "pin sem o hash resolve pela cauda");
        assert_eq!(hit.unwrap().id, "gearlever_9f2a_Hydra.desktop");
        let hit = resolve_pin(&idx, &entries, "GEARLEVER_9F2A_HYDRA.desktop");
        assert!(hit.is_some(), "caixa variada resolve pelo fold");
        assert_eq!(hit.unwrap().id, "gearlever_9f2a_Hydra.desktop");
        let hit = resolve_pin(&idx, &entries, "hydra");
        assert!(hit.is_some(), "o pin nu resolve o arquivo assinado (o reverso)");
        assert_eq!(hit.unwrap().id, "gearlever_9f2a_Hydra.desktop");
        // o exato continua o caminho feliz
        let hit = resolve_pin(&idx, &entries, "gearlever_9f2a_Hydra.desktop");
        assert_eq!(hit.unwrap().id, "gearlever_9f2a_Hydra.desktop");
        // e o que NÃO existe em nenhum dir XDG continua morto de verdade
        assert!(resolve_pin(&idx, &entries, "app-que-saiu-do-mundo.desktop").is_none());
        assert!(resolve_pin(&idx, &entries, "").is_none());
    }

    #[test]
    fn e139_a_fronteira_do_near_match_se_aplica_a_escada() {
        // a lei v2.10.6 intocada: 'foot' ⊂ 'footclient' NÃO casa (letra
        // colada é outro app) — a escada do pin não abre esta porta
        let (entries, idx) = indice_de_mentira(&["footclient.desktop"]);
        assert!(
            resolve_pin(&idx, &entries, "foot.desktop").is_none(),
            "foot NÃO vira footclient pela escada (a poda só mata o que realmente morreu)"
        );
        // e a contenção COM fronteira segue viva ('brave' ⊂ 'brave-browser')
        let (entries, idx) = indice_de_mentira(&["brave-browser.desktop"]);
        let hit = resolve_pin(&idx, &entries, "brave.desktop");
        assert!(hit.is_some(), "a contenção com fronteira segue a lei");
        assert_eq!(hit.unwrap().id, "brave-browser.desktop");
    }

    // ── 1.0-104 — o índice por NOME e a varredura COMPLETA ────────────

    #[test]
    fn a_varredura_completa_leva_o_nodisplay_do_jogo() {
        // o cenário DO DONO: o jogo Steam/Hydra deixa o .desktop com
        // NoDisplay=true em ~/.local/share/applications — a GAVETA não o
        // mostra (a lei E21), mas a IDENTIDADE da dock precisa dele
        let dir = tmpdir("desktops-todos");
        std::fs::write(
            dir.join("steam_app_413150.desktop"),
            "[Desktop Entry]\nName=Stardew Valley\nExec=proton run\nIcon=steam_icon_413150\nNoDisplay=true\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("foot.desktop"),
            "[Desktop Entry]\nName=Foot\nExec=foot\n",
        )
        .unwrap();
        // a varredura LIMPA (a gaveta): só o foot
        assert_eq!(scan_desktop_dir(&dir).len(), 1, "NoDisplay não é app de LANEÇAR");
        // a varredura COMPLETA (a dock): o jogo ENTRA como identidade
        let todos = scan_desktop_dir_todos(&dir);
        assert_eq!(todos.len(), 2, "NoDisplay é identidade de MOSTRAR");
        assert!(todos.iter().any(|e| e.id == "steam_app_413150.desktop"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn o_titulo_da_janela_resolve_o_nome_do_desktop() {
        // a rede do título: o "Stardew Valley" da JANELA casa o Name do
        // .desktop que nenhum app_id nomeia (o caso do jogo via Hydra)
        let entries = vec![
            DesktopEntry {
                id: "foot.desktop".into(),
                name: "Foot".into(),
                exec: "foot".into(),
                ..Default::default()
            },
            DesktopEntry {
                id: "steam_app_413150.desktop".into(),
                name: "Stardew Valley".into(),
                exec: "proton run".into(),
                icon: "steam_icon_413150".into(),
                ..Default::default()
            },
        ];
        let idx = name_index(&entries);
        // o título EXATO (normalizado) casa — o ícone de verdade nasce
        let hit = resolve_por_titulo(&idx, &entries, "Stardew Valley");
        assert_eq!(hit.map(|e| e.id.as_str()), Some("steam_app_413150.desktop"));
        // a caixa/acento são da casa (o fold mastiga)
        let hit = resolve_por_titulo(&idx, &entries, "stardew valley");
        assert_eq!(hit.map(|e| e.id.as_str()), Some("steam_app_413150.desktop"));
        // a contenção NÃO casa (o juízo é EXATO: o título com sufixo é
        // OUTRA janela — "Stardew Valley — Notificações" não é o jogo)
        assert!(resolve_por_titulo(&idx, &entries, "Stardew Valley — Notificações").is_none());
        // título vazio: nada honesto
        assert!(resolve_por_titulo(&idx, &entries, "  ").is_none());
        // o nome sem .desktop na lista: nada
        let idx_vazio: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        assert!(resolve_por_titulo(&idx_vazio, &entries, "Foot").is_none());
    }

    #[test]
    fn e106_o_auxiliar_nao_rouba_o_wmclass_do_dono() {
        // O CASO DO RIG: thunar-bulk-rename.desktop ordena ANTES no
        // alfabeto e carrega o MESMO StartupWMClass=Thunar — sem a lei,
        // o índice cravava o bulk-rename na chave "thunar" e o clique no
        // botão do gerenciador de arquivos abria "Renomear em massa"
        let entries = vec![
            parse_desktop_entry(
                "thunar-bulk-rename.desktop",
                "[Desktop Entry]\nName=Bulk Rename\nExec=thunar --bulk-rename\nStartupWMClass=Thunar\n",
            ),
            parse_desktop_entry(
                "thunar.desktop",
                "[Desktop Entry]\nName=Thunar\nExec=thunar\nStartupWMClass=Thunar\n",
            ),
        ];
        let idx = desktop_index(&entries);
        let hit = resolve_desktop(&idx, &entries, "thunar").unwrap();
        assert_eq!(hit.id, "thunar.desktop", "o WMClass Thunar é do DONO");
        // o auxiliar segue resolvível pelo PRÓPRIO id (um pin direto
        // dele não morre podado na 2ª passada)
        let hit = resolve_desktop(&idx, &entries, "thunar-bulk-rename").unwrap();
        assert_eq!(hit.id, "thunar-bulk-rename.desktop");
        // a família exo-* e os *-settings são auxiliares idem (pelo id
        // e pelo Exec que carrega exo-*)
        assert!(desktop_eh_auxiliar(&parse_desktop_entry(
            "exo-file-manager.desktop",
            "[Desktop Entry]\nName=File Manager\nExec=exo-open --launch FileManager\n",
        )));
        assert!(desktop_eh_auxiliar(&parse_desktop_entry(
            "thunar-settings.desktop",
            "[Desktop Entry]\nName=Thunar Settings\nExec=thunar-settings\n",
        )));
        assert!(desktop_eh_auxiliar(&parse_desktop_entry(
            "foo.desktop",
            "[Desktop Entry]\nName=Foo\nExec=exo-desktop-item-edit --type=Application\n",
        )));
        // o app de verdade e o jogo Steam NÃO são auxiliares (a
        // identidade dos jogos NoDisplay é a lei 1.0-104, intocada)
        assert!(!desktop_eh_auxiliar(&parse_desktop_entry(
            "thunar.desktop",
            "[Desktop Entry]\nName=Thunar\nExec=thunar\nStartupWMClass=Thunar\n",
        )));
        assert!(!desktop_eh_auxiliar(&parse_desktop_entry(
            "steam_app_413150.desktop",
            "[Desktop Entry]\nName=Stardew Valley\nExec=proton run\nIcon=steam_icon_413150\nNoDisplay=true\n",
        )));
    }

    #[test]
    fn e106_o_jogo_nodisplay_do_steam_segue_indexado() {
        // a lei 1.0-104 intocada pela E106/3: o jogo NoDisplay segue no
        // índice com TODAS as chaves dele (o stem do id + o binário)
        let entries = vec![parse_desktop_entry(
            "steam_app_413150.desktop",
            "[Desktop Entry]\nName=Stardew Valley\nExec=proton run\nIcon=steam_icon_413150\nNoDisplay=true\n",
        )];
        let idx = desktop_index(&entries);
        assert_eq!(
            idx.get("steam-app-413150").map(|i| entries[*i].id.as_str()),
            Some("steam_app_413150.desktop"),
            "a identidade NoDisplay do jogo segue viva no índice"
        );
    }

    #[test]
    fn e106_o_oculto_nunca_rouba_a_chave_do_visivel() {
        // O CASO DA CASA: foot-server.desktop (NoDisplay, no /usr/local
        // que ordena ANTES) carrega Exec=foot --server — o 1º binário é
        // "foot" e a chave era DELE; o clique no comm "foot" lançava o
        // DAEMON do terminal em vez do terminal
        let entries = vec![
            parse_desktop_entry(
                "foot-server.desktop",
                "[Desktop Entry]\nName=Foot Server\nExec=foot --server\nNoDisplay=true\n",
            ),
            parse_desktop_entry(
                "footclient.desktop",
                "[Desktop Entry]\nName=Foot Client\nExec=footclient\nNoDisplay=true\n",
            ),
            parse_desktop_entry(
                "foot.desktop",
                "[Desktop Entry]\nName=Foot\nExec=foot\n",
            ),
        ];
        let idx = desktop_index(&entries);
        // a chave "foot" é do TERMINAL de verdade, nunca do daemon
        let hit = resolve_desktop(&idx, &entries, "foot").unwrap();
        assert_eq!(hit.id, "foot.desktop");
        assert_eq!(hit.exec, "foot");
        // SEM o foot de verdade na lista, o oculto continua sendo a
        // identidade (o visível desocupa; ninguém APAGA o oculto)
        let so_ocultos = vec![
            parse_desktop_entry(
                "foot-server.desktop",
                "[Desktop Entry]\nName=Foot Server\nExec=foot --server\nNoDisplay=true\n",
            ),
        ];
        let idx2 = desktop_index(&so_ocultos);
        assert_eq!(
            idx2.get("foot").map(|i| so_ocultos[*i].id.as_str()),
            Some("foot-server.desktop")
        );
    }

    #[test]
    fn e106_o_primeiro_binario_entende_aspas() {
        // o Exec CITADO é um token só (o .desktop local do sem-nome cita
        // o caminho com espaço — o split cru partiria a citação)
        assert_eq!(
            first_binary("\"/opt/Apps/Hydra Plus.AppImage\" --flag"),
            Some("Hydra Plus.AppImage".to_string())
        );
        assert_eq!(first_binary("thunar --bulk-rename"), Some("thunar".to_string()));
        assert_eq!(first_binary(""), None);
    }

    #[test]
    fn e106_o_desktop_local_do_sem_nome() {
        // o id da casa: elite-<chave>.desktop (o lixo vira traço)
        assert_eq!(elite_desktop_id("hydra-plus"), "elite-hydra-plus.desktop");
        assert_eq!(elite_desktop_id("Meu Jogo"), "elite-meujogo.desktop");
        // o corpo: Name/Exec/StartupWMClass/Terminal/NoDisplay e a
        // assinatura da primeira linha (o desafixar só apaga O QUE A
        // CASA GEROU)
        let corpo = desktop_do_raw(
            "hydra-plus",
            "Hydra",
            "/opt/Apps/Hydra Plus.AppImage",
            Some(Path::new("/home/dono/.cache/elite/appimage-icons/abc.png")),
        );
        assert!(eh_desktop_da_casa(&corpo));
        assert!(corpo.contains("[Desktop Entry]\n"));
        assert!(corpo.contains("Name=Hydra\n"));
        assert!(corpo.contains("Exec=\"/opt/Apps/Hydra Plus.AppImage\"\n"));
        assert!(corpo.contains("StartupWMClass=hydra-plus\n"));
        assert!(corpo.contains("Terminal=false\n"));
        assert!(corpo.contains("NoDisplay=false\n"));
        assert!(corpo.contains("Icon=/home/dono/.cache/elite/appimage-icons/abc.png\n"));
        // SEM ícone: o campo OMITE (nunca glifo mentiroso)
        let sem_icone = desktop_do_raw("bazaar", "Bazaar", "/opt/bazaar", None);
        assert!(!sem_icone.contains("Icon="));
        // Exec sem espaço: sem aspas (a forma crua da casa)
        assert!(sem_icone.contains("Exec=/opt/bazaar\n"));
        // o papel do DONO nunca é apagado sem a assinatura
        assert!(!eh_desktop_da_casa("[Desktop Entry]\nName=x\n"));
        // e o corpo GERADO parseia de volta (a dock mesma é consumidora)
        let volta = parse_desktop_entry("elite-hydra-plus.desktop", &corpo);
        assert_eq!(volta.wm_class, "hydra-plus");
        assert_eq!(volta.exec, "\"/opt/Apps/Hydra Plus.AppImage\"");
        assert!(!volta.no_display && !volta.terminal);
    }
}
