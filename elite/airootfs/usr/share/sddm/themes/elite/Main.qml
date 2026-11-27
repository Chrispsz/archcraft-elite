// Archcraft ELITE · tema sddm `elite` — Main.qml (E106/5b)
// ─────────────────────────────────────────────────────────────────────
// O greeter 100% pt_BR na identidade da casa (o journal do rig
// fotografou a tela de login cinza/azul EM INGLÊS — "Welcome!",
// "Login", "Suspend": o tema do upstream nunca foi daqui). A peça é
// QML SIMPLES e conservador: só QtQuick + SddmComponents (o molde
// oficial dos temas SDDM — TextBox/PasswordBox/Button/ComboBox),
// zero import exótico, zero imagem — o fundo é retângulo pintado com
// a base obsidiana #111116; o acento #a855f7 é ponto de ação (o botão
// Entrar e a borda em foco), os textos vestem #f4f4f6. As cores moram
// no theme.conf (default interno idêntico — o QML não quebra sem ele).
// A data/hora no topo usa o locale pt_BR nativo do Qt; os botões de
// energia falam com o sddm (powerOff/reboot/suspend); o login é
// sddm.login(usuario, senha, índice da sessão do ComboBox).

import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root

    // ── a paleta da casa (theme.conf manda; default interno idêntico) ──
    readonly property color cor_fundo: config.background_color || "#111116"
    readonly property color cor_campo: config.field_color || "#18181f"
    readonly property color cor_acento: config.accent_color || "#a855f7"
    readonly property color cor_texto: config.text_color || "#f4f4f6"
    readonly property color cor_borda: config.border_color || "#262637"
    readonly property color cor_erro: "#f38ba8"

    color: cor_fundo

    function tenta_entrar() {
        // o índice da sessão vem do ComboBox (o sessionModel do greeter)
        sddm.login(campo_usuario.text, campo_senha.text, sessao.index)
    }

    function atualiza_relogio() {
        var agora = new Date()
        var pt_br = Qt.locale("pt_BR")
        relogio.text = Qt.formatTime(agora, "HH:mm", pt_br)
        data_pt.text = Qt.formatDate(agora, "dddd, d 'de' MMMM 'de' yyyy", pt_br)
    }

    // ── o topo: o relógio e a data em pt_BR (uma voz por tela) ──
    Column {
        anchors {
            top: parent.top
            topMargin: 56
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 6

        Text {
            id: relogio
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cor_texto
            font.pixelSize: 56
            font.bold: true
        }

        Text {
            id: data_pt
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cor_texto
            opacity: 0.75
            font.pixelSize: 18
        }
    }

    // ── o cartão: a saudação e o formulário de entrada ──
    Column {
        id: cartao
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Bem-vindo!"
            color: root.cor_texto
            font.pixelSize: 26
            font.bold: true
        }

        Text {
            text: "Usuário"
            color: root.cor_texto
            opacity: 0.75
            font.pixelSize: 13
        }

        TextBox {
            id: campo_usuario
            width: 320
            height: 36
            text: userModel.lastUser
            font.pixelSize: 14
            textColor: root.cor_texto
            backgroundColor: root.cor_campo
            borderColor: root.cor_borda
            focusColor: root.cor_acento
            Keys.onReturnPressed: campo_senha.forceActiveFocus()
        }

        Text {
            text: "Senha"
            color: root.cor_texto
            opacity: 0.75
            font.pixelSize: 13
        }

        PasswordBox {
            id: campo_senha
            width: 320
            height: 36
            font.pixelSize: 14
            textColor: root.cor_texto
            backgroundColor: root.cor_campo
            borderColor: root.cor_borda
            focusColor: root.cor_acento
            Keys.onReturnPressed: tenta_entrar()
        }

        Text {
            id: msg_erro
            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            color: root.cor_erro
            font.pixelSize: 13
        }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320
            height: 36
            text: "Entrar"
            font.pixelSize: 14
            font.bold: true
            textColor: "#111116"
            backgroundColor: root.cor_acento
            borderColor: root.cor_acento
            onClicked: tenta_entrar()
        }
    }

    // ── o rodapé: a sessão escolhida e os botões de energia ──
    Row {
        anchors {
            bottom: parent.bottom
            bottomMargin: 56
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 12

        Text {
            text: "Sessão"
            color: root.cor_texto
            opacity: 0.75
            anchors.verticalCenter: sessao.verticalCenter
            font.pixelSize: 13
        }

        ComboBox {
            id: sessao
            width: 220
            height: 32
            model: sessionModel
            mainColor: root.cor_texto
            textColor: root.cor_texto
            dropdownColor: root.cor_campo
            borderColor: root.cor_borda
        }

        Button {
            text: "Desligar"
            font.pixelSize: 13
            textColor: root.cor_texto
            backgroundColor: root.cor_campo
            borderColor: root.cor_borda
            pressedColor: root.cor_acento
            enabled: sddm.canPowerOff
            onClicked: sddm.powerOff()
        }

        Button {
            text: "Reiniciar"
            font.pixelSize: 13
            textColor: root.cor_texto
            backgroundColor: root.cor_campo
            borderColor: root.cor_borda
            pressedColor: root.cor_acento
            enabled: sddm.canReboot
            onClicked: sddm.reboot()
        }

        Button {
            text: "Suspender"
            font.pixelSize: 13
            textColor: root.cor_texto
            backgroundColor: root.cor_campo
            borderColor: root.cor_borda
            pressedColor: root.cor_acento
            enabled: sddm.canSuspend
            onClicked: sddm.suspend()
        }
    }

    // o relógio vivo: a data_pt acompanha a virada do minuto
    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: atualiza_relogio()
    }

    Component.onCompleted: {
        atualiza_relogio()
        // o foco nasce onde a dívida está: senha se o usuário veio do
        // último login, o campo vazio se a máquina é de primeira
        if (campo_usuario.text === "") {
            campo_usuario.forceActiveFocus()
        } else {
            campo_senha.forceActiveFocus()
        }
    }

    // a voz ÚNICA do fracasso (elite-danger — a senha errada fala uma vez)
    Connections {
        target: sddm
        function onLoginFailed() {
            msg_erro.text = "Senha ou usuário incorretos."
        }
    }
}
