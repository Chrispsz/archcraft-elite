// ═════════════════════════════════════════════════════════════════════════
// craft-net (1.0-109) — O SELETOR DE REDE DE 1 CLIQUE.
// A EVIDÊNCIA REAL DO DUMP 1.0-108: o clique ESQUERDO no ícone de Rede
// da top bar não executava ação nenhuma e o `nm-connection-editor`
// exige CRIAR perfis manualmente em vez de LISTAR as redes Wi-Fi
// próximas com 1 clique como o Bluetooth (a PARIDADE que o dono
// pediu). Este é o seletor da diretriz, palavra por palavra:
//
//   · status da ETHERNET (Conectar / Desconectar — a LEI DA CONEXÃO
//     PRINCIPAL de elite_core::rede: a ethernet vence, o par guarda
//     no last-net.state, a queda é `nmcli device disconnect` — NUNCA
//     `ip link set down`);
//   · as REDES Wi-Fi PRÓXIMAS (`nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY
//     device wifi list --rescan auto`) com sinal, cadeado e a marca ✓
//     da conectada — CONECTANDO COM 1 CLIQUE (a senha em diálogo
//     gráfico LIMPO apenas para redes protegidas SEM perfil salvo);
//   · a porta "Configurações avançadas (nm-connection-editor)" para
//     VPN/IP fixo — o editor técnico continua a porta de fundo.
//
// A JANELA veste a MESMA camada do pick (gtk4-layer-shell: Overlay ·
// teclado exclusivo · centralizada — a gramática do calendário da top
// bar) e a instância única mora no elite/craft-net.pid (MESMO título =
// toggle que sai limpo). Escape fecha IMEDIATO com exit 0; perder foco
// após mapeado fecha (nenhum invisível captura ponteiro).
// ═════════════════════════════════════════════════════════════════════════

#[cfg(not(feature = "gui"))]
fn main() {
    eprintln!("craft-net: o seletor de rede precisa da feature 'gui' (o CI do pacote liga — a lei L6)");
    std::process::exit(1);
}

#[cfg(feature = "gui")]
fn main() {
    use gtk4::prelude::*;

    if craft_tools::pede_ajuda(
        &[],
        "uso: craft-net — o seletor de rede de 1 clique (Ethernet + redes Wi-Fi)\n\
         \x20     — a paridade com o Bluetooth que o dono pediu\n\
         \x20  o esquerdo do ícone de Rede da top bar abre AQUI; a grade de\n\
         \x20  apps abre pela entrada Gerenciador de Rede.",
    ) {
        return;
    }

    // A INSTÂNCIA ÚNICA (a mesma lei do pick: o MESMO seletor vivo é
    // toggle que fecha e sai limpo — o clique de novo no ícone fecha)
    let pidfile = net_pid_path();
    match std::fs::read_to_string(&pidfile)
        .map(|papel| craft_tools::decide_instancia(&papel, net_do_pid_vivo, "Rede"))
        .unwrap_or(craft_tools::InstanciaPick::Livre)
    {
        craft_tools::InstanciaPick::Toggle => {
            mata_o_net_velho(&pidfile);
            sai(0);
        }
        craft_tools::InstanciaPick::Substitui => mata_o_net_velho(&pidfile),
        craft_tools::InstanciaPick::Livre => {}
    }
    if let Some(pai) = pidfile.parent() {
        let _ = std::fs::create_dir_all(pai);
    }
    let _ = std::fs::write(&pidfile, format!("{}\nRede", std::process::id()));

    let app = gtk4::Application::new(
        Some("elite.craft.Net"),
        gtk4::gio::ApplicationFlags::NON_UNIQUE,
    );
    app.connect_activate(build);
    // 1.0-109 — os argumentos são da CASA (o argv do processo NUNCA vai
    // ao parser do GLib: uma palavra torta de fora não mata o seletor)
    let _ = app.run_with_args::<&str>(&[]);
    sai(1); // o app terminou sem gesto: a saída única colhe o pidfile
}

/// A FOTO da sessão (tudo colhido em THREAD — o rescan nunca segura o
/// GTK): a Ethernet (dispositivo, ligada?) e as redes ao alcance.
#[cfg(feature = "gui")]
enum Foto {
    SemNmcli,
    Viva {
        ethernet: Option<(String, bool)>,
        redes: Vec<elite_core::rede::RedeWifi>,
    },
}

#[cfg(feature = "gui")]
fn build(app: &gtk4::Application) {
    use gtk4::prelude::*;

    craft_tools::load_css();
    let win = craft_tools::janela_camada(app, "pickwin", "Rede", "craft-net");
    win.set_default_size(520, 460);

    let corpo = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    corpo.set_margin_top(14);
    corpo.set_margin_bottom(14);
    corpo.set_margin_start(16);
    corpo.set_margin_end(16);

    // o estado na cabeça da lista (o feedback honesto de sempre: o que
    // corre agora está NA TELA, nunca no vácuo)
    let status = gtk4::Label::new(Some("Procurando redes…"));
    corpo.append(&status);

    let scroll = gtk4::ScrolledWindow::new();
    let lista = gtk4::ListBox::new();
    lista.set_selection_mode(gtk4::SelectionMode::None);
    scroll.set_child(Some(&lista));
    scroll.set_min_content_height(240);
    scroll.set_vexpand(true);
    scroll.set_max_content_height(420);

    // O ESC fecha IMEDIATO (exit 0 — o gesto do dono não é erro)
    {
        let win_c = win.clone();
        let ec = gtk4::EventControllerKey::new();
        ec.connect_key_pressed(move |_, key, _, _| {
            if key == gtk4::gdk::Key::Escape {
                win_c.close();
                return gtk4::glib::Propagation::Stop;
            }
            gtk4::glib::Propagation::Proceed
        });
        win.add_controller(ec);
    }
    // PERDEU O PALCO após mapeado = fecha (a guarda de foco do pick: o
    // primeiro frame do labwc é cortesia — o FALSE de verdade do
    // compositor é que colhe)
    {
        let ja_teve_foco = std::rc::Rc::new(std::cell::Cell::new(false));
        let nasceu = std::rc::Rc::new(std::cell::RefCell::new(std::time::Instant::now()));
        let ja = ja_teve_foco.clone();
        let nasc = nasceu.clone();
        win.connect_notify_local(Some("is-active"), move |w, _| {
            if w.is_active() {
                ja.set(true);
                return;
            }
            if !ja.get() {
                return; // o primeiro frame é cortesia
            }
            if nasc.borrow().elapsed() < std::time::Duration::from_millis(300) {
                return; // a carência do present()
            }
            sai(1); // o palco é de outro: nenhum invisível captura ponteiro
        });
    }

    // A FOTO nasce em THREAD (o rescan do Wi-Fi não segura a thread do
    // GTK JAMAIS); a chegada é o cinto de 60ms de try_recv — a thread
    // do GTK acorda SÓ até a foto chegar, zero polling eterno
    let (tx_foto, rx_foto) = std::sync::mpsc::channel::<Foto>();
    std::thread::spawn(move || {
        let _ = tx_foto.send(colhe_foto());
    });
    {
        let lista = lista.clone();
        let status = status.clone();
        let win = win.clone();
        let mut montada = false;
        gtk4::glib::timeout_add_local(std::time::Duration::from_millis(60), move || {
            if montada {
                return gtk4::glib::ControlFlow::Break; // um tiro só
            }
            match rx_foto.try_recv() {
                Ok(foto) => {
                    montada = true;
                    monta_a_lista(&lista, &status, &win, foto);
                    gtk4::glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => {
                    gtk4::glib::ControlFlow::Continue // a foto ainda vem
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    montada = true;
                    gtk4::glib::ControlFlow::Break // a thread morreu calada
                }
            }
        });
    }

    corpo.append(&scroll);
    win.set_child(Some(&corpo));
    win.present();
}

/// A LISTA MONTADA (a foto é UM tiro — a remontagem honesta do pick):
/// a Ethernet com o toggle da LEI DA CONEXÃO PRINCIPAL, as redes ao
/// alcance com o 1 clique e a porta do editor técnico no fim.
#[cfg(feature = "gui")]
fn monta_a_lista(
    lista: &gtk4::ListBox,
    status: &gtk4::Label,
    win: &gtk4::ApplicationWindow,
    foto: Foto,
) {
    use gtk4::prelude::*;

    match foto {
        Foto::SemNmcli => {
            status.set_label(
                "O NetworkManager não responde (nmcli ausente) —\nverifique o serviço com: systemctl status NetworkManager",
            );
        }
        Foto::Viva { ethernet, redes } => {
            // a ETHERNET: o status + o botão da LEI DA CONEXÃO
            // PRINCIPAL (Conectar/Desconectar — 1 clique)
            if let Some((dev, ligada)) = ethernet {
                let linha = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
                let rotulo = gtk4::Label::new(Some(&format!(
                    "Ethernet ({dev}) — {}",
                    if ligada { "conectada" } else { "desconectada" }
                )));
                rotulo.set_halign(gtk4::Align::Start);
                rotulo.set_hexpand(true);
                let botao = gtk4::Button::with_label(if ligada {
                    "Desconectar"
                } else {
                    "Conectar"
                });
                {
                    let win = win.clone();
                    botao.connect_clicked(move |_| {
                        std::thread::spawn(|| {
                            elite_core::rede::alterna_conexao_principal();
                        });
                        win.close();
                        sai(0);
                    });
                }
                linha.append(&rotulo);
                linha.append(&botao);
                lista.append(&linha);
            }
            // as REDES Wi-Fi próximas: sinal, cadeado, ✓ e o 1 CLIQUE
            // (a senha em diálogo limpo SÓ para a protegida sem perfil)
            for rede in &redes {
                let btn = gtk4::Button::with_label(&rotulo_da_rede(rede));
                btn.set_has_frame(false);
                btn.set_halign(gtk4::Align::Start);
                {
                    let win = win.clone();
                    let rede = rede.clone();
                    btn.connect_clicked(move |_| {
                        pede_conexao(&win, &rede);
                    });
                }
                lista.append(&btn);
            }
            if redes.is_empty() {
                let vazio =
                    gtk4::Label::new(Some("Nenhuma rede Wi-Fi ao alcance (o rádio está desligado?)"));
                vazio.set_halign(gtk4::Align::Start);
                lista.append(&vazio);
            }
            status.set_label(&format!(
                "{} rede(s) Wi-Fi ao alcance — 1 clique conecta",
                redes.len()
            ));
        }
    }
    // a PORTA DO EDITOR técnico no fim (VPN/IP fixo — o editor completo
    // segue sendo a porta de fundo da casa)
    let editor = gtk4::Button::with_label("Configurações avançadas (nm-connection-editor)");
    editor.set_has_frame(false);
    editor.set_halign(gtk4::Align::Start);
    editor.connect_clicked(|_| {
        let _ = std::process::Command::new("nm-connection-editor")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
        sai(0);
    });
    lista.append(&editor);
}

/// o rótulo da rede: a marca ✓ da conectada, o SSID, o sinal em barras
/// e o cadeado da protegida (o glifo na cara — o 1 clique decide o
/// resto).
#[cfg(feature = "gui")]
fn rotulo_da_rede(r: &elite_core::rede::RedeWifi) -> String {
    let marca = if r.em_uso { "✓ " } else { "" };
    let barras = match r.sinal {
        0..=24 => "▂",
        25..=49 => "▂▄",
        50..=74 => "▂▄▆",
        _ => "▂▄▆█",
    };
    let cadeado = if r.seguranca.is_empty() { "" } else { " 🔒" };
    format!("{marca}{} · {barras} · {}{cadeado}", r.ssid, r.sinal)
}

#[cfg(feature = "gui")]
fn colhe_foto() -> Foto {
    let Some(status) = elite_core::rede::nmcli_status() else {
        return Foto::SemNmcli;
    };
    // a ETHERNET: a placa no papel (o toggle merece assento em
    // qualquer estado) e o veredito da principal conectada
    let ethernet = status
        .lines()
        .map(elite_core::rede::split_nmcli_t)
        .find(|c| c.len() >= 3 && c[1] == "ethernet")
        .map(|c| {
            let dev = c[0].clone();
            let ligada = elite_core::rede::conexao_principal(&status)
                .map(|(d, _)| d == dev)
                .unwrap_or(false);
            (dev, ligada)
        });
    let redes = std::process::Command::new("nmcli")
        .args([
            "-t",
            "-f",
            "IN-USE,SSID,SIGNAL,SECURITY",
            "device",
            "wifi",
            "list",
            "--rescan",
            "auto",
        ])
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()
        .map(|o| elite_core::rede::redes_wifi(&String::from_utf8_lossy(&o.stdout)))
        .unwrap_or_default();
    Foto::Viva { ethernet, redes }
}

/// O 1 CLIQUE DA CONEXÃO: aberta ou com PERFIL salvo conecta DIRETO em
/// thread (a janela fecha na hora); a protegida SEM perfil pede a
/// senha em diálogo LIMPO e conecta com a senha dada.
#[cfg(feature = "gui")]
fn pede_conexao(win: &gtk4::ApplicationWindow, rede: &elite_core::rede::RedeWifi) {
    use gtk4::prelude::*;

    if rede.seguranca.is_empty() || tem_perfil_salvo(&rede.ssid) {
        conecta_em_thread(&rede.ssid, None);
        win.close();
        sai(0);
    }
    // o diálogo de senha (limpo: o título da rede, o campo de senha e
    // os dois botões — nada mais)
    let dlg = gtk4::Dialog::with_buttons(
        Some(&format!("Senha de {}", rede.ssid)),
        Some(win),
        gtk4::DialogFlags::MODAL,
        &[
            ("Conectar", gtk4::ResponseType::Ok),
            ("Cancelar", gtk4::ResponseType::Cancel),
        ],
    );
    dlg.set_default_response(gtk4::ResponseType::Ok);
    let corpo = dlg.content_area();
    let campo = gtk4::PasswordEntry::new();
    campo.set_show_peek_icon(true);
    campo.set_activates_default(true);
    campo.set_placeholder_text(Some("Senha do Wi-Fi"));
    campo.set_margin_top(10);
    campo.set_margin_bottom(10);
    campo.set_margin_start(14);
    campo.set_margin_end(14);
    corpo.append(&campo);
    dlg.present();
    campo.grab_focus();
    let ssid = rede.ssid.clone();
    let win = win.clone();
    dlg.connect_response(move |dlg, resp| {
        match resp {
            gtk4::ResponseType::Ok => {
                let senha = campo.text().to_string();
                dlg.close();
                win.close();
                conecta_em_thread(&ssid, Some(senha));
                sai(0);
            }
            _ => {
                dlg.close();
            }
        }
    });
}

/// A CONEXÃO na thread (o nmcli nunca segura o GTK): o 1 clique é a
/// promessa (a janela já fechou) e o feedback de erro vive no
/// notify-send quando ele existe (a escola do `note` da casa).
#[cfg(feature = "gui")]
fn conecta_em_thread(ssid: &str, senha: Option<String>) {
    let ssid = ssid.to_string();
    std::thread::spawn(move || {
        let mut cmd = std::process::Command::new("nmcli");
        cmd.args(["dev", "wifi", "connect"]).arg(&ssid);
        if let Some(s) = &senha {
            cmd.arg("password").arg(s);
        }
        let ok = cmd
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !ok {
            // o feedback honesto (o note da casa: best-effort, nunca
            // mudo quando o notify-send mora no disco)
            let _ = std::process::Command::new("notify-send")
                .args(["-a", "Elite", "-t", "8000", "Rede"])
                .arg(format!(
                    "Não foi possível conectar em {ssid} — a senha ou o sinal dizem não"
                ))
                .spawn();
        }
        std::process::exit(0);
    });
}

/// HÁ PERFIL SALVO do SSID? (`nmcli -t -f NAME connection show` — o
/// nome do perfil de Wi-Fi É o SSID na casa; protegida com perfil
/// conecta com 1 clique, sem diálogo)
#[cfg(feature = "gui")]
fn tem_perfil_salvo(ssid: &str) -> bool {
    std::process::Command::new("nmcli")
        .args(["-t", "-f", "NAME", "connection", "show"])
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .map(elite_core::rede::split_nmcli_t)
                .any(|c| c.first().map(|n| n == ssid).unwrap_or(false))
        })
        .unwrap_or(false)
}

// ── a instância única (a mesma lei do pick, o pidfile próprio) ──────

#[cfg(feature = "gui")]
fn net_pid_path() -> std::path::PathBuf {
    let dir = std::env::var("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::PathBuf::from("/tmp"));
    dir.join("elite/craft-net.pid")
}

#[cfg(feature = "gui")]
fn net_do_pid_vivo(pid: u32) -> bool {
    std::fs::read_to_string(format!("/proc/{pid}/comm"))
        .map(|c| c.trim() == "craft-net")
        .unwrap_or(false)
}

#[cfg(feature = "gui")]
fn mata_o_net_velho(pidfile: &std::path::Path) {
    let Ok(papel) = std::fs::read_to_string(pidfile) else { return };
    let Some((pid_linha, _)) = papel.split_once('\n') else { return };
    let Ok(pid) = pid_linha.trim().parse::<i32>() else { return };
    unsafe {
        libc::kill(pid, libc::SIGTERM);
    }
    for _ in 0..25 {
        if !net_do_pid_vivo(pid as u32) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let _ = std::fs::remove_file(pidfile);
}

/// A SAÍDA ÚNICA (o pidfile sai com o dono).
#[cfg(feature = "gui")]
fn sai(codigo: i32) -> ! {
    let pidfile = net_pid_path();
    if let Ok(papel) = std::fs::read_to_string(&pidfile) {
        if papel.lines().next() == Some(std::process::id().to_string().as_str()) {
            let _ = std::fs::remove_file(&pidfile);
        }
    }
    std::process::exit(codigo);
}
