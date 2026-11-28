// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — network.rs (1.0-110 T1) — A REDE NO FIO, POR EVENTO
// ═════════════════════════════════════════════════════════════════════════
// A DIRETRIZ DA DOSE (1.0-110 · Commit 2/2): o barramento da casa é VIVO —
// zero polling. A barra de era vestia o ícone de rede num belt de 5s de
// `nmcli device status` (UM FORK a cada 5s, para sempre, mesmo com o
// dono só lendo) e o plug/unplug do cabo só vestia no PRÓXIMO belt — o
// contrato de aceitação é <500 ms. A cura é o daemon PUBLICAR
// BusMsg::Network POR EVENTO: o NetworkManager fala D-Bus no SYSTEM bus
// e o daemon é o ÚNICO ouvidor (a mesma escola do bluetooth.rs 1.0-106
// e do idle.rs: o censo NASCE no arranque e cada PropertiesChanged do
// mundo externo vale um censo NOVO — a barra e a dock só assinam).
//
// O JUÍZO é PURO (a porta dos testes): o censo devolve a lista de
// dispositivos (tipo · estado · rótulo da conexão ativa) e
// `julga_dispositivos` veste o contrato tipado SEM saber de D-Bus — a
// ethernet ATIVA vence (a lei da dose de sempre: cabo é o caminho de
// menor dúvida), senão o Wi-Fi ativo, senão o Offline tipado (o botão
// NUNCA some — offline é um estado, não ausência).
//
// NM no fio (org.freedesktop.NetworkManager · system bus):
//   · GetDevices (o manager) → os object paths dos dispositivos;
//   · GetAll("org.freedesktop.NetworkManager.Device") por dispositivo
//     → DeviceType (1=ethernet · 2=wifi) + State (100=activated) +
//     Interface;
//   · o RÓTULO da conexão ativa (o Get "Id" do ActiveConnection — o
//     nome do cabo de casa ou o SSID do Wi-Fi; o rótulo é HUMANO, a
//     casa nunca mostra 'enp7s0' cru no contrato).
//   · OS SINAIS: match rule do SENDER org.freedesktop.NetworkManager
//     (tipo signal, sem filtro de interface — o PropertiesChanged
//     padrão E o legado do próprio NM, o StateChanged do dispositivo,
//     o DeviceAdded/Removed do hotplug). Sinal relevante → censo NOVO
//     → publica SE MUDOU (o idempotente cala o chatty: quality de Wi-Fi
//     não re-veste o que não mudou).
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;

use elite_core::{BusMsg, NetworkKind, NetworkState};
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

/// o estado vivo (None = o NM nunca falou — sem snapshot, sem mentira).
static NET: std::sync::Mutex<Option<NetworkState>> = std::sync::Mutex::new(None);

/// o estado para o snapshot de boas-vindas (None = NM ausente/calado).
pub fn estado() -> Option<NetworkState> {
    NET.lock().unwrap().clone()
}

/// Um dispositivo do censo (a forma PURA que o juízo veste — sem D-Bus
/// no tipo, os testes alimentam a lista direto).
#[derive(Debug, Clone, PartialEq)]
pub struct DispositivoNm {
    /// NM DeviceType: 1 = ethernet · 2 = wifi (o resto não é rede da casa)
    pub tipo: u32,
    /// NM DeviceState: 100 = activated (o único estado que é REDE viva)
    pub estado: u32,
    /// o rótulo da conexão ativa (nome do cabo de casa / SSID do Wi-Fi)
    pub rotulo: Option<String>,
}

/// A CONSTANTE do NM no fio (nm-device.h: NM_DEVICE_STATE_ACTIVATED —
/// o 100 do enum genérico desde sempre; DeviceType: NM_DEVICE_TYPE_ETHERNET=1,
/// NM_DEVICE_TYPE_WIFI=2).
pub const NM_ATIVADO: u32 = 100;
pub const NM_TIPO_ETHERNET: u32 = 1;
pub const NM_TIPO_WIFI: u32 = 2;

/// O JUÍZO PURO (a porta dos testes): a lista de dispositivos vira o
/// contrato tipado. A ETHERNET ATIVA vence (a lei da dose — cabo é o
/// caminho de menor dúvida, o Wi-Fi não rouba o assento de quem tem
/// fio), senão o Wi-Fi ativo veste o SSID no rótulo, senão o Offline
/// tipado (o botão NUNCA desaparece — estado offline é um estado).
pub fn julga_dispositivos(devs: &[DispositivoNm]) -> NetworkState {
    let mut wifi: Option<&DispositivoNm> = None;
    for d in devs {
        if d.estado != NM_ATIVADO {
            continue;
        }
        if d.tipo == NM_TIPO_ETHERNET {
            // a ETHERNET vence NA HORA (a lei: cabo > sem fio)
            return NetworkState {
                kind: NetworkKind::Cabo,
                label: d.rotulo.clone().filter(|r| !r.is_empty()),
            };
        }
        if d.tipo == NM_TIPO_WIFI && wifi.is_none() {
            wifi = Some(d);
        }
    }
    match wifi {
        Some(d) => NetworkState {
            kind: NetworkKind::Wifi,
            label: d.rotulo.clone().filter(|r| !r.is_empty()),
        },
        None => NetworkState { kind: NetworkKind::Offline, label: None },
    }
}

/// publica o estado no bus (e guarda para o snapshot da boas-vindas).
fn publica(st: NetworkState) {
    *NET.lock().unwrap() = Some(st.clone());
    crate::nucleo::pub_bus(&BusMsg::Network(st));
}

/// o CENSO: os dispositivos vivos do NM viram o contrato (None = NM
/// ausente/bus calado — o mundo sem NM é honesto no papel, nunca
/// palpite).
fn censo(c: &zbus::blocking::Connection) -> Option<NetworkState> {
    let manager = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
    )
    .ok()?;
    let devs: Vec<OwnedObjectPath> = manager.call("GetDevices", &()).ok()?;
    let mut lista: Vec<DispositivoNm> = Vec::new();
    for path in devs {
        let props = zbus::blocking::Proxy::new(
            c,
            "org.freedesktop.NetworkManager",
            path.clone(),
            "org.freedesktop.DBus.Properties",
        )
        .ok()?;
        let tudo: HashMap<String, OwnedValue> = props
            .call::<_, _, HashMap<String, OwnedValue>>(
                "GetAll",
                &("org.freedesktop.NetworkManager.Device"),
            )
            .ok()?;
        let tipo = tudo
            .get("DeviceType")
            .and_then(|v| v.downcast_ref::<u32>().ok())
            .unwrap_or(0);
        if tipo != NM_TIPO_ETHERNET && tipo != NM_TIPO_WIFI {
            continue; // bridge/vpn/tun não são a rede do ícone
        }
        let estado = tudo
            .get("State")
            .and_then(|v| v.downcast_ref::<u32>().ok())
            .unwrap_or(0);
        // o RÓTULO da conexão ativa (o Id do ActiveConnection — o nome
        // humano: 'Cabo de casa' ou o SSID; sem conexão ativa o rótulo
        // é None e o juízo veste o default da casa)
        let rotulo = if estado == NM_ATIVADO {
            rotulo_da_conexao(c, &tudo)
        } else {
            None
        };
        lista.push(DispositivoNm { tipo, estado, rotulo });
    }
    Some(julga_dispositivos(&lista))
}

/// o NOME HUMANO da conexão ativa do dispositivo: o ActiveConnection
/// aponta o objeto org.freedesktop.NetworkManager.Connection.Active
/// cujo "Id" é o nome do perfil (o SSID no Wi-Fi, o nome do cabo no
/// ethernet) — None honesto em qualquer falha do caminho.
fn rotulo_da_conexao(
    c: &zbus::blocking::Connection,
    tudo: &HashMap<String, OwnedValue>,
) -> Option<String> {
    let ativa = tudo.get("ActiveConnection")?;
    let caminho = ativa
        .downcast_ref::<zbus::zvariant::ObjectPath>()
        .ok()?
        .to_string();
    let ac = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.NetworkManager",
        caminho,
        "org.freedesktop.DBus.Properties",
    )
    .ok()?;
    let id: zbus::zvariant::OwnedValue = ac
        .call::<_, _, zbus::zvariant::OwnedValue>(
            "Get",
            &("org.freedesktop.NetworkManager.Connection.Active", "Id"),
        )
        .ok()?;
    id.downcast_ref::<String>().ok()
}

/// A THREAD: o ouvidor NM. Nasce com o CENSO (o frame 0 da barra já
/// veste a verdade) e dorme nos sinais do system bus (o cable
/// plug/unplug, o Wi-Fi ligando/desligando, o perfil subindo — cada
/// PropertiesChanged/StateChanged/DeviceAdded vale um censo NOVO e o
/// publica SE MUDOU — o idempotente cala o chatty do quality).
pub fn thread() {
    let Ok(c) = zbus::blocking::Connection::system() else {
        return; // sem system bus o mundo é honesto: nenhum snapshot
    };
    if let Some(st) = censo(&c) {
        publica(st);
    }
    // a MALHA do ouvidor: TODO sinal do NM (o remetente é a cerca — o
    // PropertiesChanged padrão de org.freedesktop.DBus.Properties E o
    // legado 'org.freedesktop.NetworkManager.PropertiesChanged' do
    // próprio manager caem aqui; o StateChanged do dispositivo e o
    // DeviceAdded/DeviceRemoved do hotplug idem).
    let regra = match zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.freedesktop.NetworkManager")
        .map(|r| r.build())
    {
        Ok(r) => r,
        Err(_) => return,
    };
    let Ok(mut iter) = zbus::blocking::MessageIterator::for_match_rule(regra, &c, Some(16)) else {
        return;
    };
    loop {
        if crate::STOP.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        for msg in iter.by_ref() {
            let Ok(msg) = msg else { continue };
            // só as notícias da REDE valem censo (PropertiesChanged ·
            // StateChanged · DeviceAdded · DeviceRemoved — o Checkpoint*
            // e o CheckPermissions são ruído interno do NM)
            let membro = msg
                .header()
                .member()
                .map(|m| m.to_string())
                .unwrap_or_default();
            let noticiavel = matches!(
                membro.as_str(),
                "PropertiesChanged" | "StateChanged" | "DeviceAdded" | "DeviceRemoved"
            );
            if !noticiavel {
                continue;
            }
            if let Some(nova) = censo(&c) {
                let mudou = *NET.lock().unwrap() != Some(nova.clone());
                if mudou {
                    publica(nova);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dev(tipo: u32, estado: u32, rotulo: Option<&str>) -> DispositivoNm {
        DispositivoNm { tipo, estado, rotulo: rotulo.map(str::to_string) }
    }

    #[test]
    fn a_ethernet_ativa_vence_o_wifi_conectado() {
        // a LEI da dose: cabo é o caminho de menor dúvida — mesmo com o
        // Wi-Fi tocando, o ícone é o DA CABO (e o rótulo é o do cabo)
        let st = julga_dispositivos(&[
            dev(NM_TIPO_WIFI, NM_ATIVADO, Some("MinhaRede")),
            dev(NM_TIPO_ETHERNET, NM_ATIVADO, Some("Cabo de casa")),
        ]);
        assert_eq!(st.kind, NetworkKind::Cabo);
        assert_eq!(st.label.as_deref(), Some("Cabo de casa"));
    }

    #[test]
    fn sem_cabo_o_wifi_veste_o_ssid_no_rotulo() {
        let st = julga_dispositivos(&[
            dev(NM_TIPO_ETHERNET, 30, None), // desconectado (cabo fora)
            dev(NM_TIPO_WIFI, NM_ATIVADO, Some("Vivo:Fibra")),
        ]);
        assert_eq!(st.kind, NetworkKind::Wifi);
        assert_eq!(st.label.as_deref(), Some("Vivo:Fibra"));
    }

    #[test]
    fn o_offline_e_um_estado_tipado_nao_um_botao_sumido() {
        // plug/unplug: sem ethernet ativa E sem wifi ativo = Offline
        let st = julga_dispositivos(&[
            dev(NM_TIPO_ETHERNET, 30, None),      // desconectado
            dev(NM_TIPO_WIFI, 20, None),           // sem associação
        ]);
        assert_eq!(st.kind, NetworkKind::Offline);
        assert!(st.label.is_none());
        // e o wifi DESLIGADO de rádio (unavailable) é o mesmo Offline
        let st = julga_dispositivos(&[dev(NM_TIPO_WIFI, 10, None)]);
        assert_eq!(st.kind, NetworkKind::Offline);
        // lista vazia idem (o NM calado nunca mente estado)
        assert_eq!(julga_dispositivos(&[]).kind, NetworkKind::Offline);
    }

    #[test]
    fn o_rotulo_vazio_e_honestamente_none() {
        // o NM às vezes entrega Id vazio — o contrato não mente vazio
        let st = julga_dispositivos(&[dev(NM_TIPO_ETHERNET, NM_ATIVADO, Some(""))]);
        assert_eq!(st.kind, NetworkKind::Cabo);
        assert!(st.label.is_none(), "rótulo vazio vira None (nunca '')");
    }

    #[test]
    fn o_bridge_e_a_vpn_nao_sao_a_rede_do_icone() {
        // o censo FILTROU no coletor (só ethernet/wifi entram na lista)
        // — o juízo prova que o tipo alheio nunca veste nada sozinho
        let st = julga_dispositivos(&[dev(13 /* NM_DEVICE_TYPE_BRIDGE */, NM_ATIVADO, Some("br0"))]);
        assert_eq!(st.kind, NetworkKind::Offline);
    }
}
