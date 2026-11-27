// ELITE · elite-daemon — scan.rs (1.0-107). A VARREDURA DE /PROC MORREU
// COM O MODO AUTOMÁTICO (a ordem do dono, diretriz 1.0-107 §6:
// "remover integralmente o modo automático… deixar o daemon LIVRE de
// varredura de processos"): a família ERE, as portas do exe/cmdline/
// environ e o bloqueio dos auxiliares do Wine (WINE_HELPER_PATS) saem
// INTEIROS com o watcher — o daemon é o orquestrador da SESSÃO (bus,
// wayland, áudio, MPRIS, vigília), nunca um detetive de processos.
// O que MORA aqui é o CLIENTE GameMode (D-Bus NATIVO — zbus blocking):
// a porta `game-notify` (o craft-game manual publica o estado REAL do
// QueryStatus no bus da sessão) e o futuro nomeado que precisar falar
// com o gamemoded SEM varrer /proc.
use zbus::blocking::Proxy;

// ── o cliente GameMode (D-Bus NATIVO — zbus blocking) ────────────────────
// A conexão é PERSISTENTE (o bash abria dbus-send por chamada — um fork
// por registro e um por status, cinco vezes mais caro que o daemon vivo).
pub type GmConn = Option<zbus::blocking::Connection>;

pub fn gm_connect() -> GmConn {
    zbus::blocking::Connection::system().ok()
}

fn gm_proxy(c: &zbus::blocking::Connection) -> zbus::Result<Proxy<'_>> {
    Proxy::new(
        c,
        "com.feralinteractive.GameMode",
        "/com/feralinteractive/GameMode",
        "com.feralinteractive.GameMode",
    )
}

/// o veredito do modo: QueryStatus 1 = ATIVO (o holder manual do dono
/// conta; jogos de fora idem — o gamemoded é o juiz de sempre).
pub fn gm_status(conn: &GmConn) -> i32 {
    let Some(c) = conn.as_ref() else { return 0 };
    let Ok(p) = gm_proxy(c) else { return 0 };
    let body = (std::process::id() as i32, std::process::id() as i32, 0i32);
    p.call::<_, _, i32>("QueryStatus", &body).unwrap_or(0)
}
