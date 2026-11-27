// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — bluetooth.rs (1.0-106) — O ESTADO DO BLUETOOTH NO FIO
// ═════════════════════════════════════════════════════════════════════════
// A FERIDA (rig do dono, dose 1.0-106): o ícone do Bluetooth na barra
// nascia CORTADO mesmo com o adaptador LIGADO — o estado inicial era
// mentiroso por construção (a barra vestia o "disabled" de fábrica e
// só re-vestia no cinto de 10s do bluetoothctl). A cura é o daemon
// ser a FONTE: consultar o BlueZ NO ARRANQUE (GetManagedObjects no
// SYSTEM bus — o Powered de cada adaptador + os dispositivos
// conectados), publicar o BluetoothState PELO BUS (o snapshot de
// boas-vindas carrega o estado — o ícone da barra nasce com a
// VERDADE no primeiro frame) e seguir ouvindo o PropertiesChanged
// do org.bluez (o adaptador liga/desliga → publica no mesmo
// instante). Zero fork de bluetoothctl no daemon — D-Bus NATIVO,
// a lei de sempre da casa 2.0.
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;
use std::sync::Mutex;

use elite_core::{BluetoothState, BusMsg};
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

/// o estado vivo (None = o BlueZ nunca falou — sem snapshot, sem mentira).
static BT: Mutex<Option<BluetoothState>> = Mutex::new(None);

/// o estado para o snapshot de boas-vindas (None = BlueZ ausente/calado).
pub fn estado() -> Option<BluetoothState> {
    BT.lock().unwrap().clone()
}

/// O JUÍZO PURO (a porta dos testes): a árvore de objetos do BlueZ (o
/// GetManagedObjects: caminho → interface → propriedade → valor) vira o
/// contrato tipado. O ADAPTADOR é o objeto com org.bluez.Adapter1 (o
/// Powered decide o ícone); o CONECTADO é o org.bluez.Device1 com
/// Connected=true (o número do tooltip).
pub fn julga_arvore(
    arvore: &HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>,
) -> BluetoothState {
    let mut radio_on = false;
    let mut connected = 0u8;
    for ifaces in arvore.values() {
        for (iface, props) in ifaces {
            if iface == "org.bluez.Adapter1" {
                if let Some(on) = props.get("Powered").and_then(|v| v.downcast_ref::<bool>().ok()) {
                    radio_on |= on;
                }
            }
            if iface == "org.bluez.Device1" {
                if let Some(true) = props.get("Connected").and_then(|v| v.downcast_ref::<bool>().ok())
                {
                    connected = connected.saturating_add(1);
                }
            }
        }
    }
    BluetoothState { radio_on, connected }
}

/// publica o estado no bus (e guarda para o snapshot da boas-vindas).
fn publica(st: BluetoothState) {
    *BT.lock().unwrap() = Some(st.clone());
    crate::nucleo::pub_bus(&BusMsg::Bluetooth(st));
}

/// o censo: a árvore de objetos do BlueZ julgada (None = bus/BlueZ
/// ausente — o mundo sem adaptador é honesto no papel, nunca palpite).
fn censo(c: &zbus::blocking::Connection) -> Option<BluetoothState> {
    let proxy = zbus::blocking::Proxy::new(
        c,
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
    )
    .ok()?;
    let arvore = proxy
        .call::<_, _, HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>>(
            "GetManagedObjects",
            &(),
        )
        .ok()?;
    Some(julga_arvore(&arvore))
}

/// A THREAD: o ouvidor BlueZ. Nasce com o CENSO (o frame 0 da barra já
/// veste a verdade) e dorme no PropertiesChanged do org.bluez (o
/// Powered do adaptador muda → o estado sobe no fio no mesmo instante).
pub fn thread() {
    // o BlueZ mora no SYSTEM bus (o barramento dos daemons de hardware)
    let Ok(c) = zbus::blocking::Connection::system() else {
        return;
    };
    if let Some(st) = censo(&c) {
        publica(st);
    }
    let regra = match zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.bluez")
        .and_then(|r| r.interface("org.freedesktop.DBus.Properties"))
        .and_then(|r| r.member("PropertiesChanged"))
        .map(|r| r.build())
    {
        Ok(r) => r,
        Err(_) => return,
    };
    let Ok(mut iter) = zbus::blocking::MessageIterator::for_match_rule(regra, &c, Some(8)) else {
        return;
    };
    loop {
        if crate::STOP.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        for msg in iter.by_ref() {
            let Ok(msg) = msg else { continue };
            let Ok((iface, dict, _invalidadas)) = msg
                .body()
                .deserialize::<(String, HashMap<String, OwnedValue>, Vec<String>)>()
            else {
                continue;
            };
            if iface != "org.bluez.Adapter1" {
                continue; // o Powered do adaptador é a notícia daqui
            }
            if dict.contains_key("Powered") {
                // o censo de novo (os conectados contam junto — a árvore
                // inteira num giro, o juízo é sempre o MESMO)
                if let Some(st) = censo(&c) {
                    publica(st);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn arvore_de(
        adaptador: Option<bool>,
        conectados: usize,
    ) -> HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>> {
        let mut arvore = HashMap::new();
        if let Some(on) = adaptador {
            let mut props = HashMap::new();
            props.insert("Powered".to_string(), OwnedValue::from(on));
            let mut ifaces = HashMap::new();
            ifaces.insert("org.bluez.Adapter1".to_string(), props);
            arvore.insert(
                OwnedObjectPath::try_from("/org/bluez/hci0").unwrap(),
                ifaces,
            );
        }
        for i in 0..conectados {
            let mut props = HashMap::new();
            props.insert("Connected".to_string(), OwnedValue::from(true));
            // o Powered do adaptador é vizinho no Device — o juízo não se
            // confunde (a interface é a cerca)
            props.insert("Powered".to_string(), OwnedValue::from(true));
            let mut ifaces = HashMap::new();
            ifaces.insert("org.bluez.Device1".to_string(), props);
            arvore.insert(
                OwnedObjectPath::try_from(format!("/org/bluez/hci0/dev_{i}")).unwrap(),
                ifaces,
            );
        }
        arvore
    }

    #[test]
    fn o_adaptador_ligado_e_o_radio_on_da_verdade() {
        // o cenário do rig: o adaptador Powered=true — o radio_on ACENDE
        let st = julga_arvore(&arvore_de(Some(true), 1));
        assert!(st.radio_on, "Powered=true = o ícone da barra é o ATIVO");
        assert_eq!(st.connected, 1, "um Device com Connected=true conta");
    }

    #[test]
    fn o_adaptador_desligado_nao_e_radio_on() {
        let st = julga_arvore(&arvore_de(Some(false), 0));
        assert!(!st.radio_on, "Powered=false = o ícone cortado é a VERDADE");
        assert_eq!(st.connected, 0);
    }

    #[test]
    fn sem_arvore_e_sem_adaptador_honesto() {
        // o BlueZ sem adaptador (rig de desktop sem dongle): a árvore vazia
        // é o OFF honesto, nunca palpite
        let st = julga_arvore(&HashMap::new());
        assert!(!st.radio_on);
        assert_eq!(st.connected, 0);
        // e o Device Powered NÃO é o rádio (a interface é a cerca: só o
        // org.bluez.Adapter1 decide o ícone)
        let so_device = arvore_de(None, 2);
        let st = julga_arvore(&so_device);
        assert!(!st.radio_on, "Device Powered não é o rádio do adaptador");
        assert_eq!(st.connected, 2);
    }
}
