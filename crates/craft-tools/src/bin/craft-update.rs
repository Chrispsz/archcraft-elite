// ═════════════════════════════════════════════════════════════════════════
// craft-update (E149) — A DOSE DIRETO NO TERMINAL.
// A diretriz do dono: execução direta e ágil, sem janela intermediária —
// o bin sobe o MOTOR já provado em campo (elite-update) pelo pkexec da
// regra 49-elite com stdio HERDADO: o output do motor corre VIVO
// no terminal e o exit code é a verdade (o papel segue em
// ~/.cache/elite/update.log — a memória do motor não muda).
// ═════════════════════════════════════════════════════════════════════════

const USO: &str = "uso: craft-update — a atualização do sistema, direto no terminal\n\
\n\
\x20  (sem argumentos)  roda a atualização AGORA (pkexec elite-update — o diálogo pergunta UMA vez)\n\
\x20  -h | --help | uso  este papel\n\
\n\
\x20  O MOTOR é o elite-update já provado em campo; este bin é a porta direta —\n\
\x20  o exit code dele é a verdade (0 = a atualização concluiu; o papel do motor\n\
\x20  mora em ~/.cache/elite/update.log).\n";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if craft_tools::pede_ajuda(&args, USO) {
        return; // a ajuda sai ANTES de qualquer elevação (lei E90)
    }
    let argv = craft_tools::args_atualizacao();
    // 1.0-109 §2.3 — O TEXTO HONESTO DA ETAPA (a diretriz: o 'digite sua
    // senha para continuar' de era MENTIA — a senha é do diálogo do
    // polkit, o que roda ANTES é a sincronização e a verificação).
    println!("ELITE · Atualização do Sistema — sincronizando repositórios e verificando pacotes");
    // 1.0-109 §2.3 — O RESUMO DOS PACOTES ANTES DE APLICAR (a diretriz:
    // o dono VÊ o que a dose veste — o pacman -Qu do usuário lista o
    // que o db CORRENTE conhece; a sync de verdade é do motor
    // privilegiado a seguir, o resumo é o retrato de agora; rc 1 do
    // pacman = 'nada novo' — a casa sabe ler o silêncio; pacman
    // ausente = sem resumo, a dose segue).
    resumo_pacotes();
    // 1.0-108 — A GUARDA DO PKEXEC ÓRFÃO: o terminal que morrer no meio
    // (HUP/INT/TERM) leva o pkexec filho JUNTO — o diálogo branco do
    // polkit nunca mais fica travado na tela (ver craft_tools::corre_com_guarda)
    let rc = craft_tools::corre_com_guarda(&argv, "craft-update");
    // 1.0-107 — O CANCELAMENTO É SILÊNCIO (a diretriz §8: "se o usuário
    // cancelar ou fechar a janela de senha do Polkit (rc=126 ou 127),
    // encerrar silenciosamente sem exibir alerta de falha" — a senha
    // fechada não é erro, é o dono mudando de ideia): nada na tela,
    // nada de pausa — o terminal fecha na hora, zero falso alarme.
    if rc == 0 {
        println!("ELITE · o sistema está atualizado.");
        pausa_enter();
    } else if rc == 126 || rc == 127 {
        // o exit 0 é a verdade do cancelamento (nada rodou, nada falhou —
        // o dono fechou a janela da senha)
        std::process::exit(0);
    } else {
        eprintln!(
            "ELITE · a atualização NÃO concluiu (rc={rc}) — a verdade acima é do motor; o papel em ~/.cache/elite/update.log."
        );
        pausa_enter();
    }
    std::process::exit(rc);
}

/// 1.0-109 §2.3 — o resumo dos pacotes disponíveis ANTES de aplicar (a
/// diretriz: "exibir o resumo dos pacotes disponíveis (pacman -Qu) antes
/// de aplicar"). O pacman -Qu roda SEM elevação (a leitura do db é de
/// usuário); a saída é "nome 1.2-3 -> 1.3-1" por linha — o N e a lista
/// vestem o terminal antes do motor subir. rc≠0 e saída vazia = nada
/// novo no db corrente (o pacman devolve 1 quando não há novidade); o
/// binário ausente cala o resumo SEM matar a dose (a porta é honesta).
fn resumo_pacotes() {
    let Ok(out) = std::process::Command::new("pacman").arg("-Qu").output() else {
        return; // sem pacman na mesa (ISO exótica/juizo): sem resumo, a dose segue
    };
    let texto = String::from_utf8_lossy(&out.stdout);
    let linhas: Vec<&str> = texto.lines().filter(|l| !l.trim().is_empty()).collect();
    if linhas.is_empty() {
        println!("ELITE · nenhum pacote novo no db corrente (o motor sincroniza antes de aplicar)");
        return;
    }
    println!("ELITE · {} pacote(s) disponíveis no db corrente:", linhas.len());
    for l in &linhas {
        println!("  {l}");
    }
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
