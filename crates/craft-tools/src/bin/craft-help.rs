// ═════════════════════════════════════════════════════════════════════════
// craft-help (E149) — O MAPA DOS COMANDOS, DIRETO NO TERMINAL.
// A diretriz do dono: ajuda é execução DIRETA e ÁGIL no terminal — a
// janela intermediária morre. O conteúdo mora em
// craft_tools::mapa_comandos (puro, testado — a fonte única do mapa; o
// contrato da suíte 35-ajuda cobra que 100% dos comandos nele existem
// de verdade). O terminal da casa (foot) já veste as cores da família.
// ═════════════════════════════════════════════════════════════════════════

const USO: &str = "uso: craft-help — o mapa dos comandos da casa (no terminal)\n\
\n\
\x20  (sem argumentos)  imprime o mapa completo no terminal\n\
\x20  -h | --help | uso  este papel\n\
\n\
\x20  A FONTE do mapa é o craft_tools::mapa_comandos (puro, testado — o contrato\n\
\x20  da suíte 35-ajuda cobra que 100% dos comandos nele existem de verdade).\n";

/// O roxo da casa no ANSI 256 (a folha mestra vestida no terminal — o
/// destaque #bb9af7 ≈ cor 183; o título em negrito, o corpo calado).
const ANSI_TITULO: &str = "\x1b[1;38;5;183m";
const ANSI_COMANDO: &str = "\x1b[1m";
const ANSI_FIM: &str = "\x1b[0m";

/// E150 — A PAUSA DO `foot -e` (a ordem do dono, base 1.0-98: o terminal
/// aberto pelo menu fechava JUNTO com o processo — o mapa sumia da tela
/// antes de ser lido). Só veste quando o stdin é TTY (o `foot -e` é TTY;
/// o pipe dos testes não espera ninguém — a prova nunca trava).
fn pausa_enter() {
    use std::io::IsTerminal;
    if !std::io::stdin().is_terminal() {
        return; // pipe/prova: sem pausa (a suíte nunca espera Enter)
    }
    println!("Pressione Enter para fechar…");
    let mut s = String::new();
    let _ = std::io::stdin().read_line(&mut s);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if craft_tools::pede_ajuda(&args, USO) {
        return; // a ajuda do verbo sai ANTES de tudo (lei E90)
    }
    // std-only de verdade: o IsTerminal do std (o libc é opcional da
    // feature gui — o núcleo std-only testa em qualquer lugar)
    use std::io::IsTerminal;
    let cor = std::io::stdout().is_terminal();
    let t = if cor { ANSI_TITULO } else { "" };
    let c = if cor { ANSI_COMANDO } else { "" };
    let f = if cor { ANSI_FIM } else { "" };
    for (secao, itens) in craft_tools::mapa_comandos() {
        println!();
        println!("{t}═══ {secao} ═══{f}");
        for (cmd, desc) in itens {
            println!("  {c}{cmd:<12}{f} {desc}");
        }
    }
    println!();
    println!(
        "Atualizar e limpar de pé: {c}craft-update{f} · {c}craft-clean{f} — o diálogo de senha pergunta UMA vez."
    );
    pausa_enter();
}
