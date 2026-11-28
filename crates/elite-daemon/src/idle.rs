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
use std::sync::OnceLock;

/// o conf da vigília (os nomes do papel da casa — compat total).
#[derive(Debug, Clone, PartialEq)]
pub struct Conf {
    /// minutos de inatividade até TRAVAR (0 = nunca sozinho)
    pub lock_min: u32,
    /// minutos de inatividade até APAGAR a tela (E150 — o gesto
    /// separado: fábrica 10; MENOR que o lock colapsa no MESMO gesto —
    /// a lei E43 de sempre)
    pub off_min: u32,
    /// minutos TRAVADO até SUSPENDER de verdade (0 = off)
    pub suspend_min: u32,
}

/// o parser do idle.conf (puro, tolerante a lixo — a lição do craft-idle:
/// linha com sufixo ('10min') não pode matar o daemon calado).
/// E150 — OFF_MIN é TEMPO PRÓPRIO agora (a ordem do dono, base 1.0-98:
/// a fábrica 5/10 — trava em 5, apaga em 10); MENOR/igual ao LOCK = o
/// gesto único E43 (um só instante, trava E apaga).
pub fn parse_conf(texto: &str) -> Conf {
    let mut lock = 5u32; // a fábrica da casa
    let mut off = 0u32; // 0 = segue o lock (o gesto único)
    let mut susp = 20u32;
    for linha in texto.lines() {
        let Some((chave, valor)) = linha.split_once('=') else { continue };
        let chave = chave.trim();
        let valor = valor.trim();
        let numero = valor.trim_end_matches("min").trim();
        let Ok(n) = numero.parse::<u32>() else { continue };
        match chave {
            "LOCK_MIN" => lock = n,
            "OFF_MIN" => off = n,
            "SUSPEND_MIN" => susp = n,
            _ => {}
        }
    }
    // E43 viva: apagar ANTES de travar não existe — colapsa no gesto único
    if off < lock {
        off = lock;
    }
    Conf { lock_min: lock, off_min: off, suspend_min: susp }
}

/// o caminho do papel (~/.config/elite/idle.conf).
pub fn conf_path() -> PathBuf {
    elite_core::elite_config_dir().join("idle.conf")
}

/// E106/5a — O RESTO DO RELÓGIO (puro): a notificação ext-idle-notify é
/// ARMADA no instante em que o degrau anterior bate (o LOCK às
/// LOCK_MIN de idleness) e o protocolo conta o SEU timeout DA ARMAÇÃO —
/// armada com o tempo INTEIRO, o degrau dispara LOCK_MIN TARDE (o
/// SUSPEND_MIN=20 batia aos 30min de ociosidade, 10min após o lock; a
/// receita swayidle da casa sempre contou LOCK/SUSPEND do MESMO zero —
/// a suspensão DEVE acontecer aos SUSPEND_MIN de ociosidade). A cura é
/// armar com o QUE FALTA: alvo − já_idle. Alvo já batido = 1s (o
/// degrau dispara na hora — a semântica swayidle de sempre).
pub fn faltam_ms(alvo_min: u32, ja_idle_min: u32) -> u32 {
    if alvo_min <= ja_idle_min {
        1_000
    } else {
        (alvo_min - ja_idle_min) * 60 * 1_000
    }
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
    trava();
    apaga();
}

/// E150 — a TRAVA sozinha (o OFF_MIN maior faz a tela apagar no TEMPO
/// DELE — o dono trava em 5 e apaga em 10).
pub fn trava() {
    // 1.0-107 — O NASCIMENTO DO LOCK SEM ESPERA MORTA: o craft-lock espera
    // o hyprlock DELE morrer (a senha do dono) — o `.status()` de era
    // pendurava o fio do chamador NO LOCK INTEIRO (o Idled do wayland e o
    // PrepareForSleep do logind viviam presos enquanto o dono não
    // digitasse). O spawn solto segue a vida DELE — e a COVEIRA colhe o
    // exit NA HORA da morte (o filho de vida longa nunca vira <defunct>
    // pendurado no daemon — a lei E152 da casa).
    if let Ok(mut filho) = std::process::Command::new("/usr/local/bin/craft-lock")
        .arg("--if-needed")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
    {
        std::thread::Builder::new()
            .name("elite-coveira-lock".into())
            .spawn(move || {
                let _ = filho.wait();
            })
            .ok();
    }
}

/// 1.0-107 — A ESPERA DA SUPERFÍCIE DO LOCK (a ordem do dono, palavra
/// por palavra: "acionar o hyprlock e aguardar ele mapear a superfície
/// ANTES de apagar as saídas com wlopm --off"): o hyprlock VIVO (comm
/// no /proc — o `--if-needed` de um lock já na tela sai 0 sem nascer
/// nada) + o assento de 400ms para o mapeamento do ext-session-lock-v1
/// (o lock PINTA antes do freeze — acordar no lock de verdade, nunca
/// numa tela preta nua). Teto de 3s: o logind só espera
/// InhibitDelayMaxSec (5s) pelos inhibitors do limiar do sono.
pub fn lock_mapeado() -> bool {
    let teto = std::time::Instant::now() + std::time::Duration::from_secs(3);
    while std::time::Instant::now() < teto {
        if crate::supervise::comm_vivo("hyprlock") {
            std::thread::sleep(std::time::Duration::from_millis(400));
            return true;
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    false
}

/// E150 — O APAGAR sozinho (o segundo tempo do gesto separado).
pub fn apaga() {
    // o wlopm fala com o compositor pela interface wlr-output-power
    let _ = std::process::Command::new("wlopm")
        .arg("--off")
        .arg("*")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}

/// 1.0-110 T3 — A CONEXÃO ZBUS SYSTEM COMPARTILHADA (a casa de era
/// abria UMA conexão POR CHAMADA — o inibidores_seguram de cada Idled
/// batido construía um fio NOVO ao logind; a conexão nasce UMA vez e
/// serve a vigília inteira: o juízo dos inibidores E o verbo do sono
/// falam pelo MESMO fio).
pub(crate) fn conn_system() -> Option<&'static zbus::blocking::Connection> {
    static CONN: OnceLock<Option<zbus::blocking::Connection>> = OnceLock::new();
    CONN
        .get_or_init(|| zbus::blocking::Connection::system().ok())
        .as_ref()
}

/// 1.0-110 T3 — A SUSPENSÃO NATIVA DA CASA (a evidência do rig: o item
/// "Suspender" do menu ⏻ disparava SÓ o hyprlock — o journalctl -b -u
/// systemd-logind registrava ZERO chamadas de suspensão): a trava nasce
/// DESACOPLADA (trava — o craft-lock --if-needed em segundo plano, sem
/// bloquear o chamador), a superfície é ESPERADA (lock_mapeado — o teto
/// de 3s e o assento de 400ms da lei de sempre) e SÓ ENTÃO o sono desce
/// pelo VERBO NATIVO org.freedesktop.login1.Manager.Suspend(true) pela
/// conexão zbus system COMPARTILHADA (com o fallback honesto para o
/// `systemctl suspend` se o D-Bus retornar erro). O verbo IPC
/// (BusReq::Suspend) e o craft-suspend vestem ESTE caminho.
pub fn suspende() {
    trava();
    lock_mapeado();
    if !dorme_login1() {
        eprintln!(
            "elite-daemon: o Suspend do logind falhou — a queda honesta veste o systemctl suspend (1.0-110 T3)"
        );
        let _ = std::process::Command::new("systemctl")
            .arg("suspend")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
    }
}

/// o verbo nativo do logind (S true = interativo): Ok = o sono desceu
/// pela via PRÓPRIA do daemon (zero fork — a lei do orquestrador).
fn dorme_login1() -> bool {
    let Some(c) = conn_system() else { return false };
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    ) else {
        return false;
    };
    p.call::<_, _, ()>("Suspend", &(true)).is_ok()
}

/// O PRÉ-SONO ATÔMICO (PrepareForSleep(true)): trava ANTES do freeze —
/// e 1.0-107, A SEQUÊNCIA SEGURA da ordem do dono: hyprlock NASCE →
/// espera a SUPERFÍCIE mapeada (lock_mapeado — o teto de 3s cobre o
/// blur do wallpaper do cache E151) → SÓ ENTÃO o wlopm --off apaga as
/// saídas (apagar antes do mapeamento congelava o link DP/HDMI sem a
/// pintura do lock — o acordar sem sinal de era).
pub fn trava_pre_sono() {
    trava();
    lock_mapeado();
    apaga();
}

/// OS INIBIDORES seguram a trava? (mídia = MPRIS tocando; jogo manual
/// = inhibitor "idle:sleep" block no logind — o holder do craft-game
/// arma OS DOIS na 1.0-107; a diretriz: "honrar rigorosamente os
/// inibidores ativos do systemd-logind (idle / sleep — reprodução de
/// vídeo no navegador e modo de jogo manual)"). O logind
/// ListInhibitors é a verdade do SISTEMA (jogos de fora também contam).
/// 1.0-107 — O WHAT COMPOSTO: "idle:sleep" chega como UMA string com
/// dois nomes — o contains casa os DOIS lados ("idle" acha "idle:sleep"
/// e "sleep" idem; um inhibitor de "sleep" PURO também segura a vigília
/// da casa: quem proibiu dormir não pode ser travado e deitado).
pub fn inibidores_seguram() -> bool {
    // 1) a mídia da casa (MPRIS tocando)
    if crate::mpris::tocando() {
        return true;
    }
    // 2) os inhibitors "idle"/"sleep" do logind (o jogo manual da casa
    //    E o de fora — modo block, delay não segura)
    // 1.0-110 T3 — A CONEXÃO COMPARTILHADA (proibido abrir por chamada):
    // o mesmo fio do verbo do sono julga os inibidores
    let Some(c) = conn_system() else {
        return false;
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
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
            let segura = what.split(':').any(|w| w == "idle" || w == "sleep");
            segura && mode != "delay"
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn o_conf_da_fabrica_quando_o_papel_falta() {
        assert_eq!(
            parse_conf(""),
            Conf { lock_min: 5, off_min: 5, suspend_min: 20 }
        );
    }

    #[test]
    fn o_conf_vivo_do_dono_e_respeitado() {
        let papel = "# o papel da casa\nLOCK_MIN=15\nOFF_MIN=15\nSUSPEND_MIN=40\n";
        assert_eq!(
            parse_conf(papel),
            Conf { lock_min: 15, off_min: 15, suspend_min: 40 }
        );
    }

    #[test]
    fn o_lixo_no_papel_nao_mata_o_daemon() {
        // 'LOCK_MIN=10min' e linha vazia: a lição do craft-idle — o
        // parser tolera e segue com a fábrica no que não souber ler
        let papel = "LOCK_MIN=10min\nSUSPEND_MIN=\n\nOFF_MIN=zzz\n";
        let c = parse_conf(papel);
        assert_eq!(c.lock_min, 10); // '10min' mastigado
        assert_eq!(c.off_min, 10); // lixo → o gesto único E43
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
    fn e150_o_off_min_e_tempo_proprio_quando_maior() {
        // a fábrica nova da ordem do dono: trava em 5, apaga em 10 — o
        // APAGAR ganha tempo PRÓPRIO (o relógio conta da INATIVIDADE,
        // não do lock)
        let c = parse_conf("LOCK_MIN=5\nOFF_MIN=10\nSUSPEND_MIN=20\n");
        assert_eq!(c, Conf { lock_min: 5, off_min: 10, suspend_min: 20 });
        // o papel SEM OFF_MIN: o gesto único de sempre (5/5)
        let c2 = parse_conf("LOCK_MIN=5\nSUSPEND_MIN=20\n");
        assert_eq!(c2.off_min, 5, "sem OFF_MIN o apagar vem junto do lock");
    }

    #[test]
    fn e43_viva_o_off_menor_que_o_lock_colapsa_no_gesto_unico() {
        // apagar ANTES de travar não existe: OFF_MIN < LOCK_MIN = o MESMO
        // instante do lock (um só gesto — o defeito da janela morta não
        // volta nem por papel digitado errado)
        let c = parse_conf("LOCK_MIN=15\nOFF_MIN=2\n");
        assert_eq!(c.off_min, 15, "OFF_MIN menor colapsa no LOCK");
    }

    #[test]
    fn e106_5a_o_resto_do_relogio_armado_no_degrau() {
        // o CASO DO RIG (LOCK=10/OFF=10/SUSPEND=20): o tipo-2 é armado
        // quando o lock bate (idle=10) — com o tempo INTEIRO (20min) o
        // protocolo disparava aos 30min de ociosidade; com o QUE FALTA
        // dispara aos 20min (a semântica swayidle da casa: LOCK/SUSPEND
        // do MESMO zero)
        assert_eq!(faltam_ms(20, 10), 10 * 60 * 1_000);
        // o APAGAR separado idem: trava em 5, apaga em 10 → o tipo-1
        // armado no lock com 5min (dispara aos 10min de idleness)
        assert_eq!(faltam_ms(10, 5), 5 * 60 * 1_000);
        // alvo já batido pelo degrau de baixo: 1s (dispara na hora —
        // SUSPEND_MIN ≤ LOCK_MIN nunca foi pausa extra no swayidle)
        assert_eq!(faltam_ms(10, 10), 1_000);
        assert_eq!(faltam_ms(5, 10), 1_000);
    }
}
