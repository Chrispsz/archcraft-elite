// ═════════════════════════════════════════════════════════════════════════
// craft-clean (E149) — A LIMPEZA DIRETO NO TERMINAL.
// A diretriz do dono: execução direta e ágil, sem janela intermediária —
// o bin sobe a FASE 1 AUTO-SEGURA (journal, paccache, órfãos de link,
// lixeira, caches regeneráveis — o escopo honesto de sempre) pelo
// pkexec da regra 49-elite com stdio HERDADO. A FASE 2 avançada
// (órfãos/runtimes/miniaturas com perguntas [s/N]) segue de pé: o
// próprio elite-clean menu no terminal (o mesmo caminho que a janela
// nomeava — agora a porta principal É o terminal).
// ═════════════════════════════════════════════════════════════════════════

const USO: &str = "uso: craft-clean — a limpeza do sistema, direto no terminal\n\
\n\
\x20  (sem argumentos)  roda a limpeza segura AGORA (pkexec elite-clean — o diálogo pergunta UMA vez)\n\
\x20  -h | --help | uso  este papel\n\
\n\
\x20  A limpeza segura NUNCA toca pastas pessoais, perfis de navegador ou confs vivas.\n\
\x20  A limpeza AVANÇADA (órfãos, runtimes de Flatpak, miniaturas) é de pé:\n\
\x20  elite-clean menu — as perguntas [s/N] vivas no terminal.\n\
\x20  O papel mora em ~/.cache/elite/clean.log.\n";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if craft_tools::pede_ajuda(&args, USO) {
        return; // a ajuda sai ANTES de qualquer elevação (lei E90)
    }
    // o DONO CERTO (o --as-root recebe usuário e home por ARGUMENTO — a
    // lição E134 do polkit-agent-helper: nada de env injection no motor)
    let usuario = std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_else(|_| "root".into());
    let home = std::env::var("HOME").unwrap_or_else(|_| "/root".into());
    let argv = craft_tools::args_limpeza(&usuario, &home);
    println!(
        "ELITE · Limpeza do Sistema — removendo caches e pacotes órfãos com segurança"
    );
    // 1.0-108 — A GUARDA DO PKEXEC ÓRFÃO: o terminal que morrer no meio
    // (HUP/INT/TERM) leva o pkexec filho JUNTO — o diálogo branco do
    // polkit nunca mais fica travado na tela (ver craft_tools::corre_com_guarda)
    let rc = craft_tools::corre_com_guarda(&argv, "craft-clean");
    // 1.0-107 — O CANCELAMENTO É SILÊNCIO (a diretriz §8: "se o usuário
    // cancelar ou fechar a janela de senha do Polkit (rc=126 ou 127),
    // encerrar silenciosamente sem exibir alerta de falha" — a senha
    // fechada não é erro, é o dono mudando de ideia): nada na tela,
    // zero falso alarme — o exit 0 é a verdade do cancelamento.
    if rc == 0 {
        println!("ELITE · limpeza CONCLUÍDA — o total liberado está no relatório acima.");
    } else if rc == 126 || rc == 127 {
        std::process::exit(0);
    } else {
        eprintln!(
            "ELITE · a limpeza NÃO completou (rc={rc}) — a verdade acima é do motor; o papel em ~/.cache/elite/clean.log."
        );
    }
    std::process::exit(rc);
}
