// ═════════════════════════════════════════════════════════════════════════
// craft-update (E149) — A DOSE DIRETO NO TERMINAL.
// A diretriz do dono: execução direta e ágil, sem janela intermediária —
// o bin sobe o MOTOR já provado em campo (elite-update) pelo pkexec da
// regra 50-elite-wheel com stdio HERDADO: o output do motor corre VIVO
// no terminal e o exit code é a verdade (o papel segue em
// ~/.cache/elite/update.log — a memória do motor não muda).
// ═════════════════════════════════════════════════════════════════════════

const USO: &str = "uso: craft-update — a dose do sistema, direto no terminal\n\
\n\
\x20  (sem argumentos)  roda a dose AGORA (pkexec elite-update — o diálogo pergunta UMA vez)\n\
\x20  -h | --help | uso  este papel\n\
\n\
\x20  O MOTOR é o elite-update já provado em campo; este bin é a porta direta —\n\
\x20  o exit code dele é a verdade (0 = a dose subiu; o papel do motor mora em\n\
\x20  ~/.cache/elite/update.log).\n";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if craft_tools::pede_ajuda(&args, USO) {
        return; // a ajuda sai ANTES de qualquer elevação (lei E90)
    }
    let argv = craft_tools::args_atualizacao();
    println!("ELITE · subindo a dose (elite-update) — o diálogo de senha pergunta UMA vez…");
    let rc = std::process::Command::new(&argv[0])
        .args(&argv[1..])
        .status()
        .map(|s| s.code().unwrap_or(1))
        .unwrap_or_else(|e| {
            eprintln!(
                "craft-update: o motor não nasceu ({e}) — o elite-update viaja no pacote da casa"
            );
            127
        });
    if rc == 0 {
        println!("ELITE · dose NO AR — o sistema está atualizado.");
    } else if rc == 126 {
        eprintln!("ELITE · a autorização foi NEGADA (senha cancelada) — nada rodou.");
    } else {
        eprintln!(
            "ELITE · a dose NÃO subiu (rc={rc}) — a verdade acima é do motor; o papel em ~/.cache/elite/update.log."
        );
    }
    // E150 — A PAUSA DO `foot -e` (a ordem do dono, base 1.0-98: o terminal
    // do menu fechava JUNTO com o processo — inclusive SEM atualizações,
    // o veredito sumia antes de ser lido). Só veste com stdin TTY (o foot
    // é TTY; o pipe da prova nunca espera Enter).
    pausa_enter();
    std::process::exit(rc);
}

/// E150 — a pausa do terminal do menu (TTY = `foot -e`; pipe = segue).
fn pausa_enter() {
    use std::io::IsTerminal;
    if !std::io::stdin().is_terminal() {
        return;
    }
    println!("Pressione Enter para fechar…");
    let mut s = String::new();
    let _ = std::io::stdin().read_line(&mut s);
}
