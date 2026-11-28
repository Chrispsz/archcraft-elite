// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — discos.rs (E190 T4) — O AUTOMOUNT NATIVO UDISKS2
// ═════════════════════════════════════════════════════════════════════════
// A diretriz: ZERO residentes legados — o udiskie (Python, ~58 MB de
// residente) sai da sessão e do autostart; o pen drive monta no EVENTO
// com a notificação na cara. O ouvidor é o PRÓPRIO daemon: o
// org.freedesktop.UDisks2 no system bus anuncia cada bloco novo no
// ObjectManager (InterfacesAdded) — quem chega com interface
// org.freedesktop.UDisks2.Filesystem, não é do sistema (HintSystem
// falso) e mora num drive removível/ótico MONTA pela via PRÓPRIA do
// D-Bus (Filesystem.Mount — o mesmo que o desktop usa, com a polkit
// da casa) e a notificação sobe pelo notify-send da casa. O CENSO de
// arranque cobre a mídia que JÁ estava na mesa quando a sessão nasceu
// (GetManagedObjects — o udiskie de era montava no login; a casa não
// perde o gesto). Zero polling: a thread DORME no iterator do bus.
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;

use zbus::zvariant::OwnedObjectPath;
use zbus::zvariant::OwnedValue;

/// o JUÍZO PURO de montagem (a porta dos testes): só a mídia REMOVÍVEL
/// ou ÓPTICA, nunca o disco do sistema (HintSystem), só o uso
/// "filesystem" (partição com sistema de arquivo de verdade — o
/// espaço vazio do pen e o crypto_LUKS ficam de fora).
pub fn deve_montar(hint_system: bool, id_usage: &str, removivel: bool, optico: bool) -> bool {
    !hint_system && id_usage == "filesystem" && (removivel || optico)
}

/// o JUÍZO DE PROPS (puro): lê o bloco de propriedades de UM objeto
/// novo do UDisks2 (a carga do InterfacesAdded/GetManagedObjects) e
/// diz SE é caso (as duas interfaces: Block E Filesystem) e QUAIS os
/// sinais do drive (None = sem drive legível — o loop interno mora
/// aqui e o drive é a palavra final).
pub fn julga_objeto(
    ifaces: &HashMap<String, HashMap<String, OwnedValue>>,
) -> Option<(bool, String, Option<String>)> {
    let bloco = ifaces.get("org.freedesktop.UDisks2.Block")?;
    let _fs = ifaces.get("org.freedesktop.UDisks2.Filesystem")?;
    let hint_system = bloco
        .get("HintSystem")
        .and_then(|v| v.downcast_ref::<bool>().ok())
        .unwrap_or(true);
    let id_usage = bloco
        .get("IdUsage")
        .and_then(|v| v.downcast_ref::<String>().ok())
        .unwrap_or_default()
        .to_string();
    let drive = bloco
        .get("Drive")
        .and_then(|v| v.downcast_ref::<zbus::zvariant::ObjectPath>().ok())
        .map(|p| p.to_string());
    Some((hint_system, id_usage, drive))
}

/// o VERBO NATIVO: Filesystem.Mount(options) pela conexão do chamador
/// — o mount point (/run/media/$USER/RÓTULO) é o do udisks2 de
/// fábrica, o mesmo que o desktop da casa. A resposta (o mount point
/// de era, vazio nas famílias novas) é lida com tolerância — o que
/// importa é o Ok.
fn monta(c: &zbus::blocking::Connection, caminho: &str) -> Result<(), zbus::Error> {
    let p = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.UDisks2",
        caminho,
        "org.freedesktop.UDisks2.Filesystem",
    )?;
    let opts: HashMap<String, OwnedValue> = HashMap::new();
    let msg = p.call_method("Mount", &(opts))?;
    // o retorno é o mount point (s) nas famílias de udisks ≤2.8 e vazio
    // nas novas — a leitura é best-effort (o Ok do call_method é o
    // veredito de que MONTOU)
    let _ = msg.body().deserialize::<String>();
    Ok(())
}

/// a NOTA da casa (o mesmo veículo do áudio: notify-send pelo swaync).
fn nota(corpo: &str) {
    let _ = std::process::Command::new("notify-send")
        .args(["-a", "Elite · Discos", "-u", "low", "-t", "4000", "Discos", corpo])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

/// o RÓTULO humano do bloco (o IdLabel do pen — a cara da notificação;
/// vazio = o nome do dispositivo de era).
fn rotulo(ifaces: &HashMap<String, HashMap<String, OwnedValue>>) -> String {
    ifaces
        .get("org.freedesktop.UDisks2.Block")
        .and_then(|b| b.get("IdLabel"))
        .and_then(|v| v.downcast_ref::<String>().ok())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .unwrap_or_else(|| "mídia removível".to_string())
}

/// O GESTO COMPLETO de um objeto novo (a thread de trabalho: o mount
/// é bloqueante — mídia lenta trava segundos — e o ouvidor segue
/// livre no bus).
fn trata_objeto(c: &zbus::blocking::Connection, caminho: &str, ifaces: &HashMap<String, HashMap<String, OwnedValue>>) {
    let Some((hint_system, id_usage, drive)) = julga_objeto(ifaces) else {
        return; // não é bloco com filesystem — o drive novo/loop interno segue a vida
    };
    if drive.is_none() {
        return; // sem drive legível o juízo é do sistema (nunca monta por palpite)
    }
    let (removivel, optico) = flags_do_drive(c, drive.as_deref().unwrap_or("/"));
    if !deve_montar(hint_system, &id_usage, removivel, optico) {
        return;
    }
    let nome = rotulo(ifaces);
    match monta(c, caminho) {
        Ok(()) => {
            eprintln!("elite-daemon discos: '{nome}' montada pelo UDisks2 (o evento vestiu o lugar do udiskie — E190)");
            nota(&format!("'{nome}' montada e pronta"));
        }
        Err(e) => {
            eprintln!("elite-daemon discos: '{nome}' — o Mount do UDisks2 falhou: {e} (nomeado, honesto)");
        }
    }
}

/// as FLAGS do drive (Removable/Optical — a palavra final do juízo:
/// o drive é quem sabe se a mídia sai no bolso).
fn flags_do_drive(c: &zbus::blocking::Connection, drive: &str) -> (bool, bool) {
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.UDisks2",
        drive,
        "org.freedesktop.DBus.Properties",
    ) else {
        return (false, false);
    };
    let le_bool = |chave: &str| -> bool {
        p.call::<_, _, OwnedValue>("Get", &("org.freedesktop.UDisks2.Drive", chave))
            .ok()
            .and_then(|v| v.downcast_ref::<bool>().ok())
            .unwrap_or(false)
    };
    (le_bool("Removable"), le_bool("Optical"))
}

/// O CENSO de arranque: a mídia que JÁ estava na mesa quando a sessão
/// nasce (o GetManagedObjects entrega o mundo inteiro — o mesmo gesto
/// de login do udiskie de era, agora sem Python residente).
fn censo(c: &zbus::blocking::Connection) {
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.UDisks2",
        "/org/freedesktop/UDisks2",
        "org.freedesktop.DBus.ObjectManager",
    ) else {
        return;
    };
    let Ok(mundo) = p.call::<_, _, HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>>(
        "GetManagedObjects",
        &(),
    ) else {
        return;
    };
    for (caminho, ifaces) in mundo {
        if julga_objeto(&ifaces).is_some() {
            trata_objeto(c, &caminho.to_string(), &ifaces);
        }
    }
}

/// A THREAD: o ouvidor do ObjectManager do UDisks2. Nasce com o CENSO
/// (a mídia pré-sessão monta no login) e dorme no iterator dos sinais
/// (InterfacesAdded — cada bloco novo vale UM gesto de montagem).
pub fn thread() {
    let Ok(c) = zbus::blocking::Connection::system() else {
        return; // sem system bus o mundo é honesto: sem automount
    };
    censo(&c);
    let regra = match zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.freedesktop.UDisks2")
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
            if crate::STOP.load(std::sync::atomic::Ordering::SeqCst) {
                return;
            }
            // só o InterfacesAdded é gesto de montagem (o Removed do
            // ObjectManager não é caso — o kernel desmonta sozinho)
            if msg
                .header()
                .member()
                .map(|m| m.as_str() != "InterfacesAdded")
                .unwrap_or(true)
            {
                continue;
            }
            let Ok((caminho, ifaces)) = msg.body().deserialize::<(
                OwnedObjectPath,
                HashMap<String, HashMap<String, OwnedValue>>,
            )>() else {
                continue;
            };
            if julga_objeto(&ifaces).is_some() {
                // o mount é bloqueante (mídia lenta) — a thread de
                // trabalho liberta o ouvidor no MESMO instante
                let c = c.clone();
                let caminho = caminho.to_string();
                std::thread::Builder::new()
                    .name("elite-discos".into())
                    .spawn(move || trata_objeto(&c, &caminho, &ifaces))
                    .ok();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn prop_bool(v: bool) -> OwnedValue {
        OwnedValue::from(v)
    }

    fn prop_str(v: &str) -> OwnedValue {
        // o Value vira OwnedValue pelo TryFrom do zvariant (a string
        // mora no Value::Str — o From direto de String não existe na
        // família OwnedValue do zvariant 4)
        zbus::zvariant::Value::from(v.to_string())
            .try_into()
            .expect("o Value::Str vira OwnedValue")
    }

    fn objeto(hint: bool, usage: &str) -> HashMap<String, HashMap<String, OwnedValue>> {
        let mut bloco = HashMap::new();
        bloco.insert("HintSystem".to_string(), prop_bool(hint));
        bloco.insert("IdUsage".to_string(), prop_str(usage));
        let mut ifaces = HashMap::new();
        ifaces.insert("org.freedesktop.UDisks2.Block".to_string(), bloco);
        ifaces.insert(
            "org.freedesktop.UDisks2.Filesystem".to_string(),
            HashMap::new(),
        );
        ifaces
    }

    #[test]
    fn o_pen_drive_monta_o_disco_do_sistema_nunca() {
        // o JUÍZO PURO: removível com filesystem monta; o disco do
        // sistema (HintSystem) NUNCA (o mount do / de era seria a
        // catastrophe); o uso que não é filesystem (crypto_LUKS, o
        // espaço vazio do pen) fica de fora
        assert!(deve_montar(false, "filesystem", true, false));
        assert!(deve_montar(false, "filesystem", false, true), "o óptico monta idem");
        assert!(!deve_montar(true, "filesystem", true, false), "o disco do sistema NUNCA");
        assert!(!deve_montar(false, "crypto", true, false), "LUKS não é filesystem");
        assert!(!deve_montar(false, "", true, false), "sem uso não há mount");
        assert!(!deve_montar(false, "filesystem", false, false), "o fixo interno fica no lugar");
    }

    #[test]
    fn o_objeto_sem_o_par_de_interfaces_nao_e_caso() {
        // SEM Block OU SEM Filesystem não é caso (o drive novo, o loop
        // interno e o objeto de gerência seguem a vida); COM o par o
        // julgamento devolve os sinais para o drive decidir
        assert!(julga_objeto(&HashMap::new()).is_none());
        let mut so_block = HashMap::new();
        so_block.insert("org.freedesktop.UDisks2.Block".to_string(), HashMap::new());
        assert!(julga_objeto(&so_block).is_none());
        let mut so_fs = HashMap::new();
        so_fs.insert(
            "org.freedesktop.UDisks2.Filesystem".to_string(),
            HashMap::new(),
        );
        assert!(julga_objeto(&so_fs).is_none());
        let (hint, uso, _) = julga_objeto(&objeto(false, "filesystem")).unwrap();
        assert!(!hint);
        assert_eq!(uso, "filesystem");
        // e o objeto sem as propriedades é conservador: HintSystem
        // default true (sem a palavra do udisks, o sistema decide)
        let mut mudo = HashMap::new();
        let mut bloco = HashMap::new();
        bloco.insert("HintSystem".to_string(), prop_bool(false));
        let mut fs = HashMap::new();
        // (o VALOR do MountPoints não é julgado — só a presença do par
        // de interfaces decide; o placeholder basta)
        fs.insert("MountPoints".to_string(), prop_bool(true));
        mudo.insert("org.freedesktop.UDisks2.Block".to_string(), bloco);
        mudo.insert("org.freedesktop.UDisks2.Filesystem".to_string(), fs);
        let (hint_mudo, uso_mudo, drive) = julga_objeto(&mudo).unwrap();
        assert!(!hint_mudo);
        assert_eq!(uso_mudo, "", "o uso ausente é honesto vazio — nunca filesystem por palpite");
        assert!(drive.is_none(), "sem Drive não há palavra final — nunca monta");
    }

    #[test]
    fn o_rotulo_vazio_tem_o_nome_da_casa() {
        // o pen SEM rótulo não notifica vazio — a cara é a da casa
        assert_eq!(rotulo(&objeto(false, "filesystem")), "mídia removível");
        let mut com_nome = objeto(false, "filesystem");
        com_nome
            .get_mut("org.freedesktop.UDisks2.Block")
            .unwrap()
            .insert("IdLabel".to_string(), prop_str("PEN DO DONO"));
        assert_eq!(rotulo(&com_nome), "PEN DO DONO");
    }
}
