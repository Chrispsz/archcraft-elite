// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — idle.rs (2.0 Fase 2) — A VIGÍLIA DA CASA
// ═════════════════════════════════════════════════════════════════════════
// O swayidle APOSENTA (a diretriz §7: a trava automática é da casa —
// o daemon é o ouvidor do ext-idle-notify-v1). Este módulo é o OFÍCIO
// da vigília:
//   · o CONF VIVO (~/.config/elite/idle.conf — o mesmo papel que o
//     craft-idle escreve desde a v1.6.1: LOCK_MIN / SUSPEND_MIN);
//   · a TRAVA E O APAGAR no MESMO GESTO (E43: hyprlock + wlopm --off
//     no mesmo tick — "acorda → já está no lock; dorme → escuro de
//     fato"; o craft-lock --if-needed não mata o hyprlock vivo);
//   · OS INIBIDORES: o jogo da casa arma um inhibitor "idle" no logind
//     (RegisterGame) e a mídia tocando (MPRIS) também segura — a trava
//     ESPERA (o pedido do dono, palavra por palavra).
//   · o PRÉ-SONO ATÔMICO: o PrepareForSleep(true) trava ANTES do
//     freeze (o logind espera os inhibitors; o hyprlock nasce na tela
//     quando o sono mergulha — "acorda no lock, sempre").
// ═════════════════════════════════════════════════════════════════════════

use std::path::PathBuf;

/// o conf da vigília (os nomes do papel da casa — compat total).
#[derive(Debug, Clone, PartialEq)]
pub struct Conf {
    /// minutos de inatividade até TRAVAR E APAGAR (0 = nunca sozinho)
    pub lock_min: u32,
    /// minutos TRAVADO até SUSPENDER de verdade (0 = off)
    pub suspend_min: u32,
}

/// o parser do idle.conf (puro, tolerante a lixo — a lição do craft-idle:
/// linha com sufixo ('10min') não pode matar o daemon calado).
pub fn parse_conf(texto: &str) -> Conf {
    let mut lock = 5u32; // a fábrica da casa
    let mut susp = 20u32;
    for linha in texto.lines() {
        let Some((chave, valor)) = linha.split_once('=') else { continue };
        let chave = chave.trim();
        let valor = valor.trim();
        let numero = valor.trim_end_matches("min").trim();
        let Ok(n) = numero.parse::<u32>() else { continue };
        match chave {
            "LOCK_MIN" => lock = n,
            "OFF_MIN" => {
                // E43: mantém IGUAL ao LOCK (um só gesto); um valor
                // diferente é ignorado com honra (o papel documenta)
                if n != lock && lock == 0 {
                    lock = n;
                }
            }
            "SUSPEND_MIN" => susp = n,
            _ => {}
        }
    }
    Conf { lock_min: lock, suspend_min: susp }
}

/// o caminho do papel (~/.config/elite/idle.conf).
pub fn conf_path() -> PathBuf {
    elite_core::elite_config_dir().join("idle.conf")
}

/// o conf VIVO (lido na ARMAÇÃO de cada ciclo — barato, zero watcher;
/// o dono muda no menu e a próxima trava já obedece).
pub fn conf_vivo() -> Conf {
    std::fs::read_to_string(conf_path())
        .map(|t| parse_conf(&t))
        .unwrap_or_else(|_| parse_conf(""))
}

/// A TRAVA E O APAGAR no MESMO GESTO (E43): o craft-lock --if-needed
/// (não mata o hyprlock vivo — o "nascido no timeout" segue) e o wlopm
/// desliga as saídas DEPOIS (a tela escura não come o unlock).
pub fn trava_e_apaga() {
    let _ = std::process::Command::new("/usr/local/bin/craft-lock")
        .arg("--if-needed")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    // o wlopm fala com o compositor pela interface wlr-output-power
    let _ = std::process::Command::new("wlopm")
        .arg("--off")
        .arg("*")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}

/// o PRÉ-SONO ATÔMICO (PrepareForSleep(true)): trava ANTES do freeze.
/// O logind segura o sono pelos inhibitors (a casa tem 5s de
/// InhibitDelayMaxSec); o hyprlock nasce na tela no mesmo instante.
pub fn trava_pre_sono() {
    trava_e_apaga();
}

/// OS INIBIDORES seguram a trava? (jogo = inhibitor "idle" block no
/// logind — o daemon ARMA um na sessão de jogo; mídia = MPRIS tocando
/// — o pedido do dono da diretriz, palavra por palavra). O logind
/// ListInhibitors é a verdade do SISTEMA (jogos de fora também contam).
pub fn inibidores_seguram() -> bool {
    // 1) a mídia da casa (MPRIS tocando)
    if crate::mpris::tocando() {
        return true;
    }
    // 2) os inhibitors "idle" do logind (o jogo da casa E o de fora)
    let Ok(c) = zbus::blocking::Connection::system() else {
        return false;
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        &c,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    ) else {
        return false;
    };
    // ListInhibitors devolve (what, who, why, mode) por linha
    let Ok(lista) = p.call::<_, _, Vec<(String, String, String, String)>>("ListInhibitors", &()) else {
        return false;
    };
    lista
        .iter()
        .any(|(what, _, _, mode)| {
            (what == "idle" || what.contains("idle")) && mode != "delay"
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn o_conf_da_fabrica_quando_o_papel_falta() {
        assert_eq!(
            parse_conf(""),
            Conf { lock_min: 5, suspend_min: 20 }
        );
    }

    #[test]
    fn o_conf_vivo_do_dono_e_respeitado() {
        let papel = "# o papel da casa\nLOCK_MIN=15\nOFF_MIN=15\nSUSPEND_MIN=40\n";
        assert_eq!(
            parse_conf(papel),
            Conf { lock_min: 15, suspend_min: 40 }
        );
    }

    #[test]
    fn o_lixo_no_papel_nao_mata_o_daemon() {
        // 'LOCK_MIN=10min' e linha vazia: a lição do craft-idle — o
        // parser tolera e segue com a fábrica no que não souber ler
        let papel = "LOCK_MIN=10min\nSUSPEND_MIN=\n\nOFF_MIN=zzz\n";
        let c = parse_conf(papel);
        assert_eq!(c.lock_min, 10); // '10min' mastigado
        assert_eq!(c.suspend_min, 20); // vazio → a fábrica
    }

    #[test]
    fn o_nunca_sozinho_e_escolha_explicita() {
        // LOCK_MIN=0 = sem trava automática (W-l manual — a escolha do
        // dono é a lei; o SUSPEND não roda sem a trava DELE)
        let c = parse_conf("LOCK_MIN=0\nSUSPEND_MIN=30\n");
        assert_eq!(c.lock_min, 0);
        assert_eq!(c.suspend_min, 30);
    }

    #[test]
    fn o_off_min_de_valor_diferente_e_ignorado_com_honra() {
        // E43: um só gesto — o OFF_MIN diferente não vira janela morta;
        // o LOCK manda (o papel da casa documenta a regra)
        let c = parse_conf("LOCK_MIN=5\nOFF_MIN=5\n");
        assert_eq!(c.lock_min, 5);
        let c2 = parse_conf("LOCK_MIN=5\nOFF_MIN=30\n");
        assert_eq!(c2.lock_min, 5); // o OFF divergente NÃO sobe o LOCK
    }
}
