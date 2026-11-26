// ═════════════════════════════════════════════════════════════════════════
// craft-audit — O JUIZ NATIVO NA LINHA DE COMANDO (1.0-103)
// ═════════════════════════════════════════════════════════════════════════
// A cara CLI do núcleo `craft_tools::audit`: cada verbo que já viveu em
// heredoc python agora é um verbo NATIVO — o juiz viaja NO PACOTE (o rig
// nunca mais acorda "SEM JUIZ no sistema"; o xmllint segue como juiz
// primário onde existe, este é o juiz EMBUTIDO de sempre).
//
//   craft-audit xml <arquivo>                       — bem-formado?
//   craft-audit menu <arquivo>                      — nenhum texto fora de tag
//   craft-audit ini [--estrito] [--secoes a,b,c] <f> — INI com seção(s)
//   craft-audit yaml <arquivo>                      — YAML bem-formado
//   craft-audit calamares <raiz>                     — confs + sequência
//   craft-audit hello <bus.sock>                    — o daemon responde?
//   craft-audit brave-bg <Local State>               — background_mode=false
//   craft-audit binds-osd <rc.xml>                   — as 5 reescritas E74
//   craft-audit exec-resolve <menu> <rc> <bindir> <packages> <build.sh>
//
// Contratos de saída (a suíte e os scripts da casa leem ESTES códigos):
//   xml/menu/ini/yaml/hello  → 0 válido · 1 inválido
//   calamares               → 0 com o resumo · 1 com o réu
//   brave-bg                → 1 já curado · 2 patch aplicado · 3 sem tocar
//   binds-osd               → 0 (n/5 reescritos, o número no stdout) · 3 zero
//   exec-resolve            → stdout "EXECUTED=n" + réus/CLEAN · 0 limpo · 1 réu
// ═════════════════════════════════════════════════════════════════════════

use std::path::Path;

fn uso() -> String {
    "uso: craft-audit <verbo> [argumentos]
  xml <arquivo>            XML bem-formado
  menu <arquivo>           gramática estrita: nenhum texto fora de tag
  ini [--estrito] [--secoes a,b,c] <arquivo>
                           INI com seção (estrito: duplicatas são réu)
  yaml <arquivo>           YAML bem-formado
  calamares <raiz>         todos os confs do Calamares + a sequência
  hello <bus.sock>          o bus.sock responde ao Hello
  brave-bg <Local State>   background_mode.enabled=false (idempotente)
  binds-osd <rc.xml>        as 5 reescritas E74 (swayosd com fallback)
  exec-resolve <menu> <rc> <bindir> <packages.add> <build.sh>
                           TODO Execute aponta para binário real"
        .to_string()
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if craft_tools::pede_ajuda(&args, &uso()) {
        return;
    }
    let Some(verbo) = args.first().map(String::as_str) else {
        eprintln!("{}", uso());
        std::process::exit(2);
    };
    let resto: Vec<String> = args[1..].to_vec();
    let codigo = match verbo {
        "xml" => cmd_le_arquivo(&resto, craft_tools::audit::xml_bem_formado),
        "menu" => cmd_le_arquivo(&resto, craft_tools::audit::menu_sem_orfao),
        "yaml" => cmd_le_arquivo(&resto, craft_tools::audit::yaml_valido),
        "ini" => cmd_ini(&resto),
        "calamares" => cmd_calamares(&resto),
        "hello" => cmd_hello(&resto),
        "brave-bg" => cmd_brave_bg(&resto),
        "binds-osd" => cmd_binds_osd(&resto),
        "exec-resolve" => cmd_exec_resolve(&resto),
        _ => {
            eprintln!("verbo desconhecido: {verbo}");
            eprintln!("{}", uso());
            2
        }
    };
    std::process::exit(codigo);
}

// o juiz simples: lê UM arquivo e devolve o veredito da função pura
fn cmd_le_arquivo(args: &[String], julga: impl Fn(&str) -> bool) -> i32 {
    let Some(caminho) = args.first() else {
        eprintln!("uso: <arquivo>");
        return 2;
    };
    let Ok(texto) = std::fs::read_to_string(caminho) else {
        eprintln!("{caminho}: ilegível/ausente");
        return 1;
    };
    if julga(&texto) {
        0
    } else {
        1
    }
}

fn cmd_ini(args: &[String]) -> i32 {
    let mut estrito = false;
    let mut exigidas: Vec<String> = Vec::new();
    let mut arquivo: Option<&String> = None;
    let mut i = 0usize;
    while i < args.len() {
        match args[i].as_str() {
            "--estrito" => estrito = true,
            "--secoes" => match args.get(i + 1) {
                Some(lista) => {
                    exigidas = lista
                        .split(',')
                        .map(str::trim)
                        .filter(|s| !s.is_empty())
                        .map(str::to_string)
                        .collect();
                    i += 1;
                }
                None => {
                    eprintln!("--secoes pede a lista (a,b,c)");
                    return 2;
                }
            },
            outro => {
                if arquivo.replace(&args[i]).is_some() || outro.starts_with("--") {
                    eprintln!("uso: ini [--estrito] [--secoes a,b,c] <arquivo>");
                    return 2;
                }
            }
        }
        i += 1;
    }
    let Some(caminho) = arquivo else {
        eprintln!("uso: ini [--estrito] [--secoes a,b,c] <arquivo>");
        return 2;
    };
    let Ok(texto) = std::fs::read_to_string(caminho) else {
        eprintln!("{caminho}: ilegível/ausente");
        return 1;
    };
    if craft_tools::audit::ini_confere(&texto, estrito, &exigidas) {
        0
    } else {
        1
    }
}

fn cmd_calamares(args: &[String]) -> i32 {
    let Some(raiz) = args.first() else {
        eprintln!("uso: calamares <raiz-do-sistema>");
        return 2;
    };
    match craft_tools::audit::calamares_confere(Path::new(raiz)) {
        Ok((confs, seq)) => {
            println!("✔ Calamares: {confs} confs YAML válidos · {seq} entradas de sequência resolúveis");
            0
        }
        Err(reu) => {
            println!("✖ {reu}");
            1
        }
    }
}

fn cmd_hello(args: &[String]) -> i32 {
    let Some(sock) = args.first() else {
        eprintln!("uso: hello <bus.sock>");
        return 2;
    };
    if craft_tools::audit::hello_bus(Path::new(sock)) {
        0
    } else {
        1
    }
}

fn cmd_brave_bg(args: &[String]) -> i32 {
    let Some(caminho) = args.first() else {
        eprintln!("uso: brave-bg <Local State>");
        return 2;
    };
    // o veredito do contrato é o exit code (1/2/3 — o chamador narra)
    craft_tools::audit::brave_bg_patch(Path::new(caminho)) as i32
}

fn cmd_binds_osd(args: &[String]) -> i32 {
    let Some(caminho) = args.first() else {
        eprintln!("uso: binds-osd <rc.xml>");
        return 2;
    };
    let Ok(texto) = std::fs::read_to_string(caminho) else {
        eprintln!("{caminho}: ilegível/ausente");
        return 3;
    };
    let (novo, n) = craft_tools::audit::binds_osd_reescreve(&texto);
    if n == 0 {
        return 3; // nada a reescrever: o rc já é da era nova
    }
    if std::fs::write(caminho, &novo).is_err() {
        return 3;
    }
    println!("E74: {n}/5 binds reescritos");
    0
}

fn cmd_exec_resolve(args: &[String]) -> i32 {
    if args.len() != 5 {
        eprintln!("uso: exec-resolve <menu.xml> <rc.xml> <bindir> <packages.add> <build.sh>");
        return 2;
    }
    let (menu, rc, bindir, pkgfile, buildfile) = (
        Path::new(&args[0]),
        Path::new(&args[1]),
        Path::new(&args[2]),
        Path::new(&args[3]),
        Path::new(&args[4]),
    );
    let (total, reus) = craft_tools::audit::resolve_exec(menu, rc, bindir, pkgfile, buildfile);
    println!("EXECUTED={total}");
    if reus.is_empty() {
        println!("CLEAN");
        0
    } else {
        for r in &reus {
            println!("{r}");
        }
        1
    }
}
