// ═════════════════════════════════════════════════════════════════════════
// craft-tools::audit — O JUIZ NATIVO DA CASA (1.0-103 — a erradicação do Python)
// ═════════════════════════════════════════════════════════════════════════
// A diretriz da dose (a radiografia de linguagens): ZERO Python no repo —
// nem arquivo .py nem bloco embutido. Todo julgamento/parsing de config
// (XML/INI/YAML/JSON), o aperto de mão do bus.sock e a resolução de
// Execute do menu/rc que viviam em heredocs python migram PARA CÁ, em
// Rust std-only testável (a lei do degrau: o núcleo compila em qualquer
// lugar; a pele GTK fica na feature "gui").
//
//   · `xml_bem_formado`     — o juiz de bem-formado (a era do fallback
//                             python ElementTree morre; o xmllint segue
//                             como juiz primário onde existe, este é o
//                             juiz EMBUTIDO que viaja no pacote);
//   · `menu_sem_orfao`      — a gramática E146: nenhum texto fora de tag
//                             (o membro órfão do E103 nunca atravessa);
//   · `ini_confere`         — a lição E137 (INI sem seção) + o estrito
//                             do fuzzel.ini (seções main/colors/border);
//   · `yaml_valido`         — o gate da v1.1 (Calamares confs);
//   · `calamares_confere`   — o porte integral do validate-calamares.py
//                             (parse de TODOS os .conf + a resolução das
//                             instâncias @id da sequência contra o
//                             settings.conf — o que o Calamares real faz);
//   · `hello_bus`           — a prova de fala do bus.sock (o cliente
//                             elite-core de verdade, nunca uma imitação);
//   · `brave_bg_patch`      — o patch background_mode.enabled=false do
//                             Local State (JSON de verdade, idempotente);
//   · `binds_osd_reescreve` — as 5 reescritas EXATAS E74 (swayosd-client
//                             com fallback pactl/brightnessctl);
//   · `resolve_exec`        — a resolução executiva de TODO Execute do
//                             menu.xml ∪ rc.xml (o porte do juízo da
//                             fase 40 da suíte — sh, foot -e, for chains).
// ═════════════════════════════════════════════════════════════════════════

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::time::Duration;

// ── XML: bem-formado (a máquina de estados mínima sobre o quick-xml) ──────

/// Julga o XML BEM-FORMADO (declaração, UM root, tags casadas, nada de
/// conteúdo após o fechamento do root — os contratos do parser real).
pub fn xml_bem_formado(texto: &str) -> bool {
    use quick_xml::events::Event;
    let mut leitor = quick_xml::Reader::from_str(texto);
    leitor.config_mut().trim_text(false);
    let mut buf = Vec::new();
    // profundidade de tags abertas: 0 fora do root; `ja_fechou` guardou o
    // fechamento do root (depois dele só resta whitespace/comentário/Eof)
    let mut profundidade = 0usize;
    let mut ja_fechou = false;
    loop {
        match leitor.read_event_into(&mut buf) {
            Ok(Event::Start(_)) => {
                if ja_fechou {
                    return false; // segundo root: dois documentos colados
                }
                profundidade += 1;
            }
            Ok(Event::End(_)) => {
                if profundidade == 0 {
                    return false; // fechamento sem abertura correspondente
                }
                profundidade -= 1;
                if profundidade == 0 {
                    ja_fechou = true;
                }
            }
            Ok(Event::Empty(_)) => {
                if ja_fechou {
                    return false;
                }
                // elemento vazio é root completo quando nada está aberto
                if profundidade == 0 {
                    ja_fechou = true;
                }
            }
            Ok(Event::Text(t)) => {
                if texto_evento_sujo(&t) && profundidade == 0 {
                    return false; // texto FORA do root: lixo
                }
                // o escape valida as entidades (&amp; sem fechar é réu —
                // o parser real recusa; o quick-xml cru aceitaria)
                if t.unescape().is_err() {
                    return false; // entidade crua/inválida
                }
                // texto dentro de tag é legítimo no XML comum (o rc.xml
                // tem <gap>10</gap>) — só conta como conteúdo do root
            }
            Ok(Event::CData(_)) => {
                if profundidade == 0 {
                    return false;
                }
                // CDATA é texto legítimo dentro do root
            }
            Ok(Event::Comment(_) | Event::PI(_)) => {}
            Ok(Event::Decl(_)) => {
                if profundidade != 0 || ja_fechou {
                    return false; // declaração só antes do root
                }
            }
            Ok(Event::DocType(_)) => {
                if profundidade != 0 || ja_fechou {
                    return false; // DOCTYPE só antes do root
                }
            }
            Err(_) => return false, // aninhamento quebrado, entidade ruim…
            Ok(Event::Eof) => break,
        }
        buf.clear();
    }
    ja_fechou // um root DEU entrada e fechou
}

/// A gramática E146 do MENU: bem-formado E nenhum TEXTO em membro algum
/// (nem el.text nem el.tail — o membro órfão fora de tag é defeito).
pub fn menu_sem_orfao(texto: &str) -> bool {
    use quick_xml::events::Event;
    let mut leitor = quick_xml::Reader::from_str(texto);
    leitor.config_mut().trim_text(false);
    let mut buf = Vec::new();
    loop {
        match leitor.read_event_into(&mut buf) {
            Ok(Event::Text(t)) => {
                if texto_evento_sujo(&t) {
                    return false; // texto em qualquer lugar: membro órfão
                }
            }
            Ok(Event::CData(t)) => {
                if texto_evento_sujo(&t) {
                    return false; // CDATA é texto no ElementTree também
                }
            }
            Ok(Event::Start(_) | Event::End(_) | Event::Empty(_))
            | Ok(Event::Comment(_) | Event::Decl(_) | Event::PI(_))
            | Ok(Event::DocType(_)) => {}
            Err(_) => return false,
            Ok(Event::Eof) => return true,
        }
    }
}

/// O conteúdo de um evento Text/CData é sujo (não-whitespace)?
/// (o escape não fabrica espaço — o julgamento bruto é fiel)
fn texto_evento_sujo(t: &[u8]) -> bool {
    !t.iter().all(|&b| b.is_ascii_whitespace() || b == 0x0d || b == 0x0a || b == 0x09)
}

// ── INI: a lição E137 + o estrito do fuzzel.ini ──────────────────────────

/// Julga um INI no espírito do configparser: seções `[nome]`, `chave =
/// valor` (ou `:`), comentários `#`/`;` de linha inteira, continuação por
/// indentação — e a regra da casa: pelo menos UMA seção (o fuzzel.ini
/// quebrado da E137 morreu de seção ausente). `estrito` rejeita seções e
/// chaves duplicadas (o strict=True do juízo original); `exigidas` é o
/// subconjunto obrigatório (main/colors/border do fuzzel).
pub fn ini_confere(texto: &str, estrito: bool, exigidas: &[String]) -> bool {
    let mut secoes: BTreeSet<String> = BTreeSet::new();
    let mut chaves: BTreeSet<(String, String)> = BTreeSet::new();
    let mut secao_atual: Option<String> = None;
    for linha in texto.lines() {
        let sem_indent = linha.trim_start();
        if sem_indent.is_empty() || sem_indent.starts_with('#') || sem_indent.starts_with(';') {
            continue;
        }
        if linha.starts_with([' ', '\t']) {
            // continuação de valor: só legítima sob uma chave já nascida
            if secao_atual.is_none() {
                return false;
            }
            continue;
        }
        if sem_indent.starts_with('[') {
            if !sem_indent.ends_with(']') || sem_indent.len() < 3 {
                return false;
            }
            let nome = sem_indent[1..sem_indent.len() - 1].trim().to_string();
            if nome.is_empty() {
                return false;
            }
            let novo = !secoes.contains(&nome);
            if estrito && !novo {
                return false; // seção duplicada (strict)
            }
            secoes.insert(nome.clone());
            secao_atual = Some(nome);
            continue;
        }
        // chave: a seção TEM de existir (MissingSectionHeaderError real)
        let Some(secao) = secao_atual.as_ref() else {
            return false;
        };
        let antes = sem_indent
            .split(['=', ':'])
            .next()
            .unwrap_or("")
            .trim()
            .to_string();
        if antes.is_empty() || antes.contains(char::is_whitespace) {
            return false; // linha solta sem = nem : — lixo que o parser real recusa
        }
        if estrito && !chaves.insert((secao.clone(), antes)) {
            return false; // chave duplicada na seção (strict)
        }
    }
    if secoes.is_empty() {
        return false; // INI sem seção NENHUMA (a lição E137)
    }
    exigidas.iter().all(|ex| secoes.contains(ex))
}

// ── YAML: o gate da v1.1 (Calamares) ────────────────────────────────────

/// Julga o YAML bem-formado (o gate que a ISO v1.1 não tinha — o
/// shellprocess_btrfs quebrou o instalador no rig do dono).
pub fn yaml_valido(texto: &str) -> bool {
    yaml_rust2::YamlLoader::load_from_str(texto).is_ok()
}

// ── Calamares: o porte integral do validate-calamares.py ─────────────────

/// O que o Calamares real faz: parseia TODOS os .conf como YAML e resolve
/// as instâncias @id da sequência contra a seção `instances` do
/// settings.conf. Ok = (nº de confs, nº de entradas de sequência).
pub fn calamares_confere(raiz: &Path) -> Result<(usize, usize), String> {
    let cal = raiz.join("etc/calamares");
    if !cal.is_dir() {
        return Err(format!("{} não existe — raiz errada?", cal.display()));
    }
    let mut arquivos = vec![cal.join("settings.conf")];
    if let Ok(modulos) = std::fs::read_dir(cal.join("modules")) {
        let mut confs: Vec<_> = modulos
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|e| e == "conf"))
            .collect();
        confs.sort();
        arquivos.extend(confs);
    }
    let mut ruins: Vec<String> = Vec::new();
    for f in &arquivos {
        let texto = std::fs::read_to_string(f).unwrap_or_default();
        if yaml_rust2::YamlLoader::load_from_str(&texto).is_err() {
            ruins.push(format!("{}: YAML INVÁLIDO", f.display()));
        }
    }
    if !ruins.is_empty() {
        return Err(format!(
            "YAML INVÁLIDO no Calamares (o instalador recusaria o módulo): {}",
            ruins.join(" · ")
        ));
    }
    use yaml_rust2::yaml::Yaml;
    let sc_texto = std::fs::read_to_string(cal.join("settings.conf")).unwrap_or_default();
    let sc = yaml_rust2::YamlLoader::load_from_str(&sc_texto)
        .map_err(|_| "settings.conf do Calamares não parseia".to_string())?
        .into_iter()
        .next()
        .ok_or("settings.conf vazio")?;
    let Yaml::Hash(h) = &sc else {
        return Err("settings.conf do Calamares não é um mapeamento".to_string());
    };
    let mut inst: BTreeMap<String, String> = BTreeMap::new();
    if let Some(Yaml::Array(insts)) = h.get(&Yaml::String("instances".into())) {
        for i in insts {
            let Yaml::Hash(hi) = i else { continue };
            let module = hi.get(&Yaml::String("module".into())).and_then(Yaml::as_str).unwrap_or("");
            let id = hi.get(&Yaml::String("id".into())).and_then(Yaml::as_str).unwrap_or("");
            let cfg = hi.get(&Yaml::String("config".into())).and_then(Yaml::as_str);
            let mid = format!("{module}@{id}");
            let cfg = cfg.map(str::to_string).unwrap_or_else(|| format!("{mid}.conf"));
            inst.insert(mid, cfg);
        }
    }
    let mut seq: Vec<String> = Vec::new();
    if let Some(Yaml::Array(fases)) = h.get(&Yaml::String("sequence".into())) {
        for fase in fases {
            let Yaml::Hash(hf) = fase else { continue };
            for chave in ["show", "exec"] {
                if let Some(Yaml::Array(entradas)) = hf.get(&Yaml::String(chave.into())) {
                    seq.extend(entradas.iter().filter_map(Yaml::as_str).map(str::to_string));
                }
            }
        }
    }
    for m in &seq {
        if !m.contains('@') {
            continue;
        }
        let Some(cfg) = inst.get(m) else {
            return Err(format!("sequência referencia {m} SEM instância declarada"));
        };
        if !cal.join("modules").join(cfg).exists() {
            return Err(format!("instância {m}: config modules/{cfg} AUSENTE"));
        }
    }
    Ok((arquivos.len(), seq.len()))
}

// ── bus.sock: a prova de fala (o cliente elite-core de verdade) ──────────

/// Conecta no bus.sock, se apresenta (Hello) e exige UM quadro de volta —
/// o snapshot de boas-vindas que só o daemon vivo responde (teto de 2s).
pub fn hello_bus(sock: &Path) -> bool {
    let Some(mut fio) = elite_core::ipc::connect_bus(sock) else {
        return false;
    };
    let _ = fio.set_read_timeout(Some(Duration::from_secs(2)));
    let _ = fio.set_write_timeout(Some(Duration::from_secs(2)));
    let hello = elite_core::BusMsg::Hello {
        who: "craft-audit".to_string(),
    };
    if elite_core::ipc::send_frame(&mut fio, &hello).is_err() {
        return false;
    }
    matches!(elite_core::ipc::recv_frame(&mut fio), Ok(Some(_)))
}

// ── Brave: o patch background_mode (JSON de verdade, idempotente) ───────

/// Os códigos do contrato original: 1 = já curado (nada a fazer) ·
/// 2 = patch aplicado (escrita atômica) · 3 = perfil exótico/corrompido
/// (sem tocar). O dono do arquivo é preservado pelo chamador.
pub fn brave_bg_patch(caminho: &Path) -> u8 {
    let Ok(bytes) = std::fs::read(caminho) else {
        return 3;
    };
    let Ok(mut doc) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
        return 3;
    };
    if !doc.is_object() {
        return 3;
    }
    if let Some(bm) = doc.get("background_mode") {
        if bm.get("enabled") == Some(&serde_json::Value::Bool(false)) {
            return 1; // idempotente: a chave false não é reescrita
        }
    }
    let bm = doc
        .as_object_mut()
        .expect("julgado objeto acima")
        .entry("background_mode")
        .or_insert_with(|| serde_json::json!({}));
    if !bm.is_object() {
        *bm = serde_json::json!({});
    }
    bm.as_object_mut()
        .expect("objeto recém-vestido")
        .insert("enabled".to_string(), serde_json::Value::Bool(false));
    let Ok(novo) = serde_json::to_vec(&doc) else {
        return 3;
    };
    if elite_core::persist::write_atomic(caminho, &novo).is_err() {
        return 3;
    }
    2
}

// ── E74: as 5 reescritas EXATAS dos binds de volume/brilho ───────────────

/// As 5 reescritas do rc.xml (pactl/brightnessctl → swayosd-client com
/// fallback): devolve (novo texto, nº de binds reescritos).
pub fn binds_osd_reescreve(texto: &str) -> (String, usize) {
    const REGRAS: [(&str, &str); 5] = [
        (
            r#"command="pactl set-sink-volume @DEFAULT_SINK@ +5%""#,
            r#"command="sh -c 'swayosd-client --volume +5 || pactl set-sink-volume @DEFAULT_SINK@ +5%'""#,
        ),
        (
            r#"command="pactl set-sink-volume @DEFAULT_SINK@ -5%""#,
            r#"command="sh -c 'swayosd-client --volume -5 || pactl set-sink-volume @DEFAULT_SINK@ -5%'""#,
        ),
        (
            r#"command="pactl set-sink-mute @DEFAULT_SINK@ toggle""#,
            r#"command="sh -c 'swayosd-client --volume mute-toggle || pactl set-sink-mute @DEFAULT_SINK@ toggle"'""#,
        ),
        (
            r#"command="brightnessctl set +10%""#,
            r#"command="sh -c 'swayosd-client --brightness +10% || brightnessctl set +10%'""#,
        ),
        (
            r#"command="brightnessctl set 10%-""#,
            r#"command="sh -c 'swayosd-client --brightness -10% || brightnessctl set 10%-'"#,
        ),
    ];
    let mut novo = texto.to_string();
    let mut n = 0usize;
    for (de, para) in REGRAS {
        if novo.contains(de) {
            novo = novo.replace(de, para);
            n += 1;
        }
    }
    (novo, n)
}

// ── a resolução executiva de TODO Execute (menu.xml ∪ rc.xml) ────────────

/// O shlex do python (posix: aspas consumidas, escapes fora de aspas) —
/// None = aspas/escapes desbalanceados (o comando é réu, não o juiz).
pub fn shlex_split(s: &str) -> Option<Vec<String>> {
    let mut toks: Vec<String> = Vec::new();
    let mut atual = String::new();
    let mut tem_atual = false;
    let mut aspas: Option<char> = None;
    let mut escapado = false;
    for ch in s.chars() {
        if escapado {
            atual.push(ch);
            tem_atual = true;
            escapado = false;
            continue;
        }
        match ch {
            '\\' if aspas.is_none() => {
                escapado = true;
                tem_atual = true;
            }
            '\\' if aspas == Some('"') => {
                atual.push(ch);
                tem_atual = true;
            }
            '\'' if aspas.is_none() => {
                aspas = Some('\'');
                tem_atual = true;
            }
            '\'' if aspas == Some('\'') => {
                aspas = None;
            }
            '"' if aspas.is_none() => {
                aspas = Some('"');
                tem_atual = true;
            }
            '"' if aspas == Some('"') => {
                aspas = None;
            }
            c if c.is_whitespace() && aspas.is_none() => {
                if tem_atual {
                    toks.push(std::mem::take(&mut atual));
                    tem_atual = false;
                }
            }
            c => {
                atual.push(c);
                tem_atual = true;
            }
        }
    }
    if escapado || aspas.is_some() {
        return None; // desbalanceado: shlex levantaria ValueError
    }
    if tem_atual {
        toks.push(atual);
    }
    Some(toks)
}

/// A resolução de TODO `action name="Execute"` do menu ∪ rc: cada
/// comando aponta para um binário REAL (airootfs, compilado, pacote,
/// alias ou base do sistema) — devolve (total, réus).
pub fn resolve_exec(
    menu: &Path,
    rc: &Path,
    bindir: &Path,
    pkgfile: &Path,
    buildfile: &Path,
) -> (usize, Vec<String>) {
    let mut airootfs: BTreeSet<String> = BTreeSet::new();
    if let Ok(rd) = std::fs::read_dir(bindir) {
        for e in rd.flatten() {
            if let Some(n) = e.file_name().to_str() {
                airootfs.insert(n.to_string());
            }
        }
    }
    let mut pacotes: BTreeSet<String> = BTreeSet::new();
    if let Ok(txt) = std::fs::read_to_string(pkgfile) {
        for ln in txt.lines() {
            let l = ln.trim();
            if !l.is_empty() && !l.starts_with('#') {
                if let Some(primeiro) = l.split_whitespace().next() {
                    pacotes.insert(primeiro.to_string());
                }
            }
        }
    }
    let mut compilados: BTreeSet<String> = [
        "elite-daemon", "craft-bar-rs", "craft-dock-rs", "craft-dump",
        "craft-update", "craft-clean", "craft-help", "craft-pick", "craft-audit",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    if let Ok(src) = std::fs::read_to_string(buildfile) {
        let re = regex::Regex::new(r"for b in ([a-z0-9 \-]+) do").expect("regex literal da casa");
        for m in re.captures_iter(&src) {
            if let Some(grupo) = m.get(1) {
                for b in grupo.as_str().split_whitespace() {
                    compilados.insert(b.to_string());
                }
            }
        }
    }
    let aliases: BTreeMap<&str, &str> = [
        ("blueman-manager", "blueman"), ("blueman-adapters", "blueman"),
        ("wl-copy", "wl-clipboard"), ("wl-paste", "wl-clipboard"),
        ("pactl", "libpulse"), ("swayosd-client", "swayosd"), ("brave", "brave-origin"),
        ("xauth", "xorg-xauth"), ("xhost", "xorg-xhost"), ("7z", "7zip"),
        ("paccache", "pacman-contrib"),
    ]
    .into_iter()
    .collect();
    let base: BTreeSet<&str> =
        ["sh", "systemctl", "xdg-open", "zsh", "gsettings", "loginctl", "env"]
            .into_iter()
            .collect();
    let palavras: BTreeSet<&str> = [
        "for", "in", "do", "done", "if", "then", "else", "elif", "fi",
        "exec", "export", "command", "local", "return", "while", "case", "esac",
    ]
    .into_iter()
    .collect();

    let resolve = |b: &str| -> bool {
        airootfs.contains(b)
            || compilados.contains(b)
            || pacotes.contains(b)
            || aliases.get(b).is_some_and(|a| pacotes.contains(*a))
            || base.contains(b)
    };

    // o primeiro binário principal de um comando (a gramática da casa:
    // foot wrapper, sh -c, ${TERMINAL:-X}, cadeia for, senão 1º token útil)
    let primeiro_binario = |cmd: &str| -> Option<String> {
        let cmd = cmd.trim();
        let toks = shlex_split(cmd)?;
        let mut toks = toks;
        if toks.first().map(String::as_str) == Some("foot") {
            if toks.len() == 1 {
                return Some("foot".to_string());
            }
            toks.remove(0);
            // 1.0-104 — AS FLAGS DO foot CAEM ANTES DO -e (o menu vestiu
            // o craft-help com a GEOMETRIA `foot -W 115x28 -e`: o juízo
            // antigo parava no VALOR da flag como se fosse binário):
            // o -e é o TERMINADOR — as outras flags caem com o VALOR
            // colado (o token seguinte que não começa com '-')
            while let Some(t) = toks.first().cloned() {
                if t == "-e" {
                    toks.remove(0);
                    break;
                }
                if t.starts_with('-') {
                    toks.remove(0);
                    if !toks.is_empty() && !toks[0].starts_with('-') {
                        toks.remove(0); // o valor da flag (115x28 do -W)
                    }
                    continue;
                }
                break; // corpo direto sem -e: o token é o alvo
            }
        }
        let mut corpo = toks.join(" ");
        if let Some(resto) = corpo.strip_prefix("sh -c ") {
            corpo = resto.to_string();
        } else if corpo.starts_with("sh -c") {
            corpo = corpo.replacen("sh -c", "", 1).trim_start_matches(char::is_whitespace).to_string();
        }
        let re_term = regex::Regex::new(r"\$\{TERMINAL:-(\w[\w\-]*)\}").expect("regex literal");
        if let Some(m) = re_term.captures(&corpo) {
            return Some(m[1].to_string());
        }
        let re_chain =
            regex::Regex::new(r"for\s+\w+\s+in\s+([\w\.\-]+(?:\s+[\w\.\-]+)*)\s*;").expect("regex literal");
        if let Some(m) = re_chain.captures(&corpo) {
            if let Some(primeiro) = m[1].split_whitespace().next() {
                return Some(primeiro.to_string());
            }
        }
        let plano = corpo
            .replace("&&", " ")
            .replace("||", " ")
            .replace([';', '|'], " ");
        for t in shlex_split(&plano).unwrap_or_default() {
            if palavras.contains(t.as_str())
                || t.starts_with('-')
                || t.contains('=')
                || t.contains('/')
                || t.starts_with('$')
            {
                continue;
            }
            return Some(t);
        }
        None
    };

    let mut total = 0usize;
    let mut reus: Vec<String> = Vec::new();
    for arq in [menu, rc] {
        let texto = std::fs::read_to_string(arq).unwrap_or_default();
        let nome = arq.file_name().and_then(|n| n.to_str()).unwrap_or("?").to_string();
        for comando in comandos_execute(&texto) {
            total += 1;
            match primeiro_binario(&comando) {
                None => reus.push(format!("{nome}: Execute sem binário principal: {}", comando.chars().take(60).collect::<String>())),
                Some(prim) => {
                    if !resolve(&prim) {
                        reus.push(format!(
                            "{nome}: '{prim}' não existe na casa (command='{}')",
                            comando.chars().take(60).collect::<String>()
                        ));
                    }
                }
            }
        }
    }
    // os fósseis históricos NUNCA voltam como Execute (a mordaça da casa)
    const FOSSEIS: [&str; 11] = [
        "craft-drawer", "craft-bars", "craft-connect", "craft-menu",
        "craft-player", "craft-power", "craft-logout", "craft-audio-route",
        "craft-dock-gui", "craft-pin-pick", "craft-toplevel",
    ];
    for arq in [menu, rc] {
        let texto = std::fs::read_to_string(arq).unwrap_or_default();
        let nome = arq.file_name().and_then(|n| n.to_str()).unwrap_or("?").to_string();
        for f in FOSSEIS {
            if texto.contains(&format!("command=\"{f}")) || texto.contains(&format!(" {f} ")) {
                // o grep literal do juízo original: command="…fóssil…"
                let re = regex::Regex::new(&format!(r#"command="([^"]*\b{}\b[^"]*)""#, regex::escape(f)))
                    .expect("regex de fóssil");
                for m in re.captures_iter(&texto) {
                    reus.push(format!(
                        "{nome}: fóssil '{f}' em Execute (command='{}')",
                        m[1].chars().take(50).collect::<String>()
                    ));
                }
            }
        }
    }
    (total, reus)
}

/// Os valores de `command` de todo `<action name="Execute" .../>` do texto
/// (atributo em elemento vazio ou par aberto/fechado — a gramática labwc).
fn comandos_execute(texto: &str) -> Vec<String> {
    use quick_xml::events::Event;
    let mut leitor = quick_xml::Reader::from_str(texto);
    let mut buf = Vec::new();
    let mut comandos = Vec::new();
    loop {
        match leitor.read_event_into(&mut buf) {
            Ok(Event::Start(e)) | Ok(Event::Empty(e)) => {
                if e.name().as_ref() == b"action" {
                    let mut nome = String::new();
                    let mut comando = String::new();
                    for a in e.attributes().flatten() {
                        if a.key.as_ref() == b"name" {
                            nome = String::from_utf8_lossy(&a.value).into_owned();
                        } else if a.key.as_ref() == b"command" {
                            comando = String::from_utf8_lossy(&a.value).into_owned();
                        }
                    }
                    if nome == "Execute" {
                        comandos.push(comando);
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(_) => break, // XML quebrado: o juízo xml_ok acusa antes
            _ => {}
        }
        buf.clear();
    }
    comandos
}

// ── o molde dos testes do núcleo (a lei do degrau: std-only) ─────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xml_bem_formado_julga_os_dois_lados() {
        assert!(xml_bem_formado("<labwc_menu><menu /></labwc_menu>"));
        assert!(xml_bem_formado(
            "<?xml version=\"1.0\"?><!-- c --><a x=\"1\"><b>texto</b></a>"
        ));
        assert!(!xml_bem_formado("<a><b></a></b>")); // aninhamento quebrado
        assert!(!xml_bem_formado("<a></a><b></b>")); // dois roots colados
        assert!(!xml_bem_formado("<a></a>lixo")); // conteúdo após o root
        assert!(!xml_bem_formado("<a>")); // root aberto
        assert!(xml_bem_formado("<a>&amp;&#231;</a>")); // entidades legítimas
        assert!(!xml_bem_formado("<a>&amp</a>")); // entidade sem fechar
    }

    #[test]
    fn menu_sem_orfao_acusa_o_membro_fora_de_tag() {
        assert!(menu_sem_orfao("<menu><item /></menu>"));
        assert!(menu_sem_orfao("<menu>\n  <item />\n</menu>")); // só whitespace
        assert!(!menu_sem_orfao("<menu>texto</menu>")); // el.text sujo
        assert!(!menu_sem_orfao("<menu><item /></menu> órfão")); // el.tail sujo
        assert!(!menu_sem_orfao("<menu><![CDATA[x]]></menu>")); // CDATA é texto
        assert!(!menu_sem_orfao("<menu><item")); // quebrado nem chega a ser menu
    }

    #[test]
    fn ini_confere_a_licao_e137_e_o_estrito_do_fuzzel() {
        let bom = "[main]\nfont=monospace\n[colors]\nbackground=000000\n";
        assert!(ini_confere(bom, false, &[]));
        assert!(ini_confere(bom, true, &[]));
        let exigidas = ["main".into(), "colors".into(), "border".into()];
        assert!(ini_confere(&format!("{bom}[border]\nwidth=1\n"), true, &exigidas));
        assert!(!ini_confere(bom, true, &exigidas)); // border ausente
        assert!(!ini_confere("font=monospace\n", false, &[])); // sem seção NENHUMA
        assert!(!ini_confere("[main]\na=1\na=2\n", true, &[])); // chave duplicada
        // comentários e continuação legítimos:
        assert!(ini_confere("# nota\n; outra\n[main]\nfont=mono\n  continuação\n", true, &[]));
    }

    #[test]
    fn yaml_valido_julga_o_gate_da_v11() {
        assert!(yaml_valido("chave: valor\nlista:\n  - a\n  - b\n"));
        assert!(yaml_valido("# só comentário\n"));
        assert!(!yaml_valido("chave: [fechando\n"));
        assert!(!yaml_valido("a: 1\n b: 2:\n c [\n"));
    }

    #[test]
    fn calamares_confere_resolve_as_instancias_da_sequencia() {
        let raiz = std::env::temp_dir().join(format!("elite-calamares-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&raiz);
        let cal = raiz.join("etc/calamares/modules");
        std::fs::create_dir_all(&cal).unwrap();
        std::fs::write(
            raiz.join("etc/calamares/settings.conf"),
            "# comentário\nsequence:\n  - show:\n      - welcome\n  - exec:\n      - shellprocess@btrfs\ninstances:\n  - id: btrfs\n    module: shellprocess\n    config: btrfs.conf\n",
        )
        .unwrap();
        std::fs::write(cal.join("btrfs.conf"), "script: \"echo ok\"\n").unwrap();
        let (n, k) = calamares_confere(&raiz).expect("conf válido");
        assert_eq!(n, 2); // settings.conf + btrfs.conf
        assert_eq!(k, 2); // welcome + shellprocess@btrfs
        // a instância apontando para config AUSENTE:
        std::fs::write(
            raiz.join("etc/calamares/settings.conf"),
            "sequence:\n  - exec:\n      - shellprocess@sumido\ninstances:\n  - id: sumido\n    module: shellprocess\n    config: sumido.conf\n",
        )
        .unwrap();
        assert!(calamares_confere(&raiz).is_err());
        // YAML quebrado num módulo:
        std::fs::write(cal.join("btrfs.conf"), "script: [quebrado\n").unwrap();
        std::fs::write(
            raiz.join("etc/calamares/settings.conf"),
            "sequence:\n  - exec:\n      - shellprocess@btrfs\ninstances:\n  - id: btrfs\n    module: shellprocess\n    config: btrfs.conf\n",
        )
        .unwrap();
        assert!(calamares_confere(&raiz).is_err());
        let _ = std::fs::remove_dir_all(&raiz);
    }

    #[test]
    fn shlex_split_e_aspas_sagradas() {
        assert_eq!(shlex_split("foot -e craft-game menu").unwrap()[0], "foot");
        assert_eq!(shlex_split("a 'b c' \"d e\"").unwrap(), ["a", "b c", "d e"]);
        assert_eq!(shlex_split(r#"exec "${TERMINAL:-foot}""#).unwrap(), ["exec", "${TERMINAL:-foot}"]);
        assert_eq!(shlex_split("a\\ b").unwrap(), ["a b"]); // escape fora de aspas
        assert!(shlex_split("aspas 'abertas").is_none());
        assert!(shlex_split("barra \\").is_none());
    }

    #[test]
    fn binds_osd_reescreve_as_5_exatas() {
        let rc = "<keybind><action name=\"Execute\" command=\"pactl set-sink-volume @DEFAULT_SINK@ +5%\" /></keybind>";
        let (novo, n) = binds_osd_reescreve(rc);
        assert_eq!(n, 1);
        assert!(novo.contains("swayosd-client --volume +5 || pactl set-sink-volume"));
        assert_eq!(binds_osd_reescreve(rc).0.matches("swayosd-client").count(), 1);
        let (n2, n) = binds_osd_reescreve(&novo);
        assert_eq!(n, 0); // idempotente
        assert_eq!(n2, novo);
    }

    #[test]
    fn brave_bg_patch_os_tres_veredictos() {
        let dir = std::env::temp_dir().join(format!("elite-brave-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("Local State");
        // exótico/corrompido: 3
        std::fs::write(&f, "não é json").unwrap();
        assert_eq!(brave_bg_patch(&f), 3);
        // curado: 1
        std::fs::write(&f, r#"{"background_mode":{"enabled":false}}"#).unwrap();
        assert_eq!(brave_bg_patch(&f), 1);
        // patch: 2 + o valor fica false (idempotente na 2ª rodada)
        std::fs::write(&f, r#"{"background_mode":{"enabled":true},"outra":1}"#).unwrap();
        assert_eq!(brave_bg_patch(&f), 2);
        assert_eq!(brave_bg_patch(&f), 1);
        let d: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        assert_eq!(d["background_mode"]["enabled"], serde_json::Value::Bool(false));
        assert_eq!(d["outra"], serde_json::Value::from(1)); // o resto preservado
        // sem background_mode nenhum: nasce o objeto
        std::fs::write(&f, r#"{"a":1}"#).unwrap();
        assert_eq!(brave_bg_patch(&f), 2);
        let d: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        assert_eq!(d["background_mode"]["enabled"], serde_json::Value::Bool(false));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_exec_julga_binarios_reais_e_fosseis() {
        let dir = std::env::temp_dir().join(format!("elite-resolve-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let bin = dir.join("bin");
        let skel = dir.join("skel");
        std::fs::create_dir_all(&bin).unwrap();
        std::fs::create_dir_all(&skel).unwrap();
        std::fs::write(bin.join("craft-lock"), "#!/bin/sh\n").unwrap();
        let menu = skel.join("menu.xml");
        let rc = skel.join("rc.xml");
        std::fs::write(
            &menu,
            "<menu><item label=\"Fechar\"><action name=\"Execute\" command=\"craft-lock\" /></item>\
             <item label=\"Terminal\"><action name=\"Execute\" command=\"foot\" /></item>\
             <item label=\"Jogo\"><action name=\"Execute\" command=\"foot -e craft-game menu\" /></item>\
             <item label=\"Ajuda\"><action name=\"Execute\" command=\"foot -W 115x28 -e craft-help\" /></item></menu>",
        )
        .unwrap();
        std::fs::write(
            &rc,
            "<labwc_config><keybind key=\"W-x\"><action name=\"Execute\" command=\"foot\" /></keybind>\
             <keybind key=\"W-y\"><action name=\"Execute\" command=\"sh -c 'swayosd-client --volume +5 || pactl set-sink-volume @DEFAULT_SINK@ +5%'\" /></keybind></labwc_config>",
        )
        .unwrap();
        let pkgf = dir.join("packages.add");
        std::fs::write(&pkgf, "# comentário\nfoot\nswayosd\nlibpulse\ncraft-game\ncraft-help\n").unwrap();
        let buildf = dir.join("build.sh");
        std::fs::write(&buildf, "    for b in craft-update craft-clean do\n        :\n    done\n").unwrap();
        let (total, reus) = resolve_exec(&menu, &rc, &bin, &pkgf, &buildf);
        assert_eq!(total, 6);
        assert!(reus.is_empty(), "réus inesperados: {reus:?}");
        // binário inexistente é réu:
        std::fs::write(
            &menu,
            "<menu><item label=\"X\"><action name=\"Execute\" command=\"binario-fantasma\" /></item></menu>",
        )
        .unwrap();
        let (total, reus) = resolve_exec(&menu, &rc, &bin, &pkgf, &buildf);
        assert_eq!(total, 3);
        assert!(reus.iter().any(|r| r.contains("binario-fantasma")));
        // fóssil é réu mesmo existindo:
        std::fs::write(
            &menu,
            "<menu><item label=\"X\"><action name=\"Execute\" command=\"craft-bars\" /></item></menu>",
        )
        .unwrap();
        let (_, reus) = resolve_exec(&menu, &rc, &bin, &pkgf, &buildf);
        assert!(reus.iter().any(|r| r.contains("fóssil 'craft-bars'")));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
