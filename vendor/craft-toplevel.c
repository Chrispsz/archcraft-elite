/* ═══════════════════════════════════════════════════════════════════════════
 * Archcraft ELITE · craft-toplevel (v1.0) — o ALT-TAB da dock
 * ═══════════════════════════════════════════════════════════════════════════
 * POR QUÊ EXISTE (o dono, ao pedir a v2.10 com navegação entre janelas):
 *   "teria como fazer ela com a dock tendo meio que essa funcionalidade de
 *    alt tab perfeitamente pra navegar entre os programas abertos e etc ou
 *    até mesmo um atalho pra isso clicável na dock".
 *
 * O BLOQUEIO QUE MORREU AQUI: a v2.10.0 documentou a limitação honesta —
 * "multi-janela com ciclo por janela exige falar o protocolo direto" —
 * porque o wlr-foreign-toplevel não tem CLI de listagem (o wlrctl só casa
 * app_id exato, sem listar e sem escolher QUAL janela). Este daemon É o
 * protocolo direto: um cliente Wayland de ~400 linhas que fala
 * zwlr_foreign_toplevel_management_v1 com o labwc e serve a sessão para a
 * dock (e qualquer cliente da Elite) num socket UNIX, linha a linha:
 *
 *   PING                    → PONG
 *   LIST                    → W|<id>|<flags>|<rank>|<app_id>|<title>  (rank 0
 *                             = janela usada mais recentemente; MRU do
 *                             alt-tab)  … final:  OK|<focused_id|0>
 *   ACT <id>                → unset_minimized + activate (RESTAURA
 *                             minimizada por COMANDO DO PROTOCOLO — a
 *                             "hipótese forte" da v2.10.0 virou lei)
 *   CLOSE <id>              → close (WM_DELETE gracioso, não kill)
 *   CYCLE                   → foca a PRÓXIMA janela no anel MRU depois da
 *                             focada — o Alt-Tab clicável, sem preview
 *
 * FLAGS: 1=maximized 2=minimized 4=activated 8=fullscreen.
 * ESTADO OTIMISTA: ACT/CYCLE movem a janela ao topo do MRU na hora (o
 * evento do compositor confirma depois) — cliques rápidos no comutador
 * caminham pelo anel em vez de re-mirar a mesma janela.
 *
 * LEIS DA CASA respeitadas:
 *   · SEM preview — o comutador da dock mostra o ÍCONE do destino, nunca
 *     miniatura (minimalista, diretriz do dono);
 *   · SUPERVISÃO — morreu, o craft-bars reinicia em ≤5s e o stderr cai no
 *     bars.log (a lição do burn test v1.6.2: nada morre calado);
 *   · SEGUNDA INSTÂNCIA = no-op — o socket vivo é detectado por connect()
 *     antes de qualquer unlink (o restart do supervisor nunca rouba o
 *     socket de quem já está servindo);
 *   · MINIMALISMO — dependência ÚNICA: libwayland-client (já vai na ISO
 *     pelo labwc). Sem GLib, sem thread, sem fd extra.
 *
 * BUILD: makepkg do [elite-local] (a mesma esteira do wlrctl vendado —
 * gcc -O2 -Wall -Wextra, sha256 da fonte pinado no PKGBUILD).
 * ═══════════════════════════════════════════════════════════════════════════ */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>

/* ── o protocolo, declarado à mão (o XML oficial é estável; a suíte da
 *    Elite trava os opcodes críticos: unset_minimized=3, activate=4,
 *    close=5, estado activated=2) ─────────────────────────────────────── */
enum { TL_SET_MAXIMIZED = 0, TL_UNSET_MAXIMIZED, TL_SET_MINIMIZED,
       TL_UNSET_MINIMIZED, TL_ACTIVATE, TL_CLOSE };
enum { EVT_TITLE = 0, EVT_APP_ID, EVT_OUT_ENTER, EVT_OUT_LEAVE,
       EVT_STATE, EVT_DONE, EVT_CLOSED };

/* dispatcher no-op (eventos do seat que ninguém lê) */
static int noop_dispatcher(const void *data, void *target, uint32_t opcode,
                           const struct wl_message *msg,
                           union wl_argument *args)
{
    (void)data; (void)target; (void)opcode; (void)msg; (void)args;
    return 0;
}

static const struct wl_interface tl_iface;

/* types É um ARRAY de ponteiros para wl_interface (assim gera o scanner):
 * o índice casa com o argumento — o new_id do evento `toplevel` PRECISA do
 * tipo real, é o que manda o demarshal do cliente CRIAR o proxy */
static const struct wl_interface *mgr_evt_types[] = { &tl_iface, NULL };

static const struct wl_message mgr_requests[] = { { "stop", "", NULL } };
static const struct wl_message mgr_events[] = {
    { "toplevel", "n", mgr_evt_types },
    { "finished", "", NULL },
};
static const struct wl_message tl_requests[] = {
    { "set_maximized", "", NULL },
    { "unset_maximized", "", NULL },
    { "set_minimized", "", NULL },
    { "unset_minimized", "", NULL },
    { "activate", "o", NULL },
    { "close", "", NULL },
    { "set_rectangle", "oiiii", NULL },
    { "destroy", "", NULL },
    { "set_fullscreen", "?o", NULL },
    { "unset_fullscreen", "", NULL },
};
static const struct wl_message tl_events[] = {
    { "title", "s", NULL },
    { "app_id", "s", NULL },
    { "output_enter", "o", NULL },
    { "output_leave", "o", NULL },
    { "state", "a", NULL },
    { "done", "", NULL },
    { "closed", "", NULL },
    { "parent", "o", NULL },
};
static const struct wl_interface tl_iface = {
    "zwlr_foreign_toplevel_handle_v1", 3,
    10, tl_requests,
    8, tl_events,
};
static const struct wl_interface mgr_iface = {
    "zwlr_foreign_toplevel_manager_v1", 3,
    1, mgr_requests,
    2, mgr_events,
};

/* ── estado das janelas ──────────────────────────────────────────────── */
#define F_MAXIMIZED 1u
#define F_MINIMIZED 2u
#define F_ACTIVATED 4u
#define F_FULLSCREEN 8u

typedef struct Tl {
    struct wl_proxy *proxy;
    uint32_t id;            /* id estável desta sessão do daemon          */
    uint32_t flags;
    int rank;               /* 0 = topo do MRU                            */
    char app_id[128];
    char title[512];
    int dead;
} Tl;

#define MAX_WIN 256
#define MAX_MRU MAX_WIN
static Tl *wins[MAX_WIN];   /* ponteiro ESTÁVEL: o Tl vive no heap e NUNCA
                             * muda de endereço — o dispatcher_data do proxy e
                             * as entradas do mru[] apontam para ele; compactar
                             * move o PONTEIRO, nunca o objeto (a revisão 3-a
                             * provou que mover struct = estado fantasma) */
static int n_wins = 0;
static Tl *mru[MAX_MRU];
static int n_mru = 0;
static uint32_t next_id = 1;

static struct wl_proxy *seat_proxy = NULL;
static struct wl_display *disp = NULL;
static int mgr_bound = 0;

static void mru_promote(Tl *t)
{
    int i, j;
    for (i = 0; i < n_mru; i++)
        if (mru[i] == t)
            break;
    if (i == n_mru) {
        if (n_mru >= MAX_MRU) {
            return;
        }
        n_mru++;
    }
    for (j = i; j > 0; j--)
        mru[j] = mru[j - 1];
    mru[0] = t;
    for (j = 0; j < n_mru; j++)
        mru[j]->rank = j;
}

static void mru_remove(Tl *t)
{
    int i, j;
    for (i = 0; i < n_mru; i++)
        if (mru[i] == t)
            break;
    if (i == n_mru)
        return;
    for (j = i; j < n_mru - 1; j++)
        mru[j] = mru[j + 1];
    n_mru--;
    for (j = 0; j < n_mru; j++)
        mru[j]->rank = j;
}

static void mru_optimistic_focus(Tl *t)
{
    int i;
    for (i = 0; i < n_wins; i++)
        wins[i]->flags &= ~(uint32_t)F_ACTIVATED;
    t->flags |= F_ACTIVATED;
    mru_promote(t);
}

/* ── dispatcher das janelas (eventos do compositor) ──────────────────── */
static int tl_dispatcher(const void *data, void *target, uint32_t opcode,
                         const struct wl_message *msg, union wl_argument *args)
{
    (void)target; (void)msg;
    /* libwayland: o 1º parâmetro É o dispatcher_data do add_dispatcher —
     * a janela. O `target` é o proxy, NUNCA o dado. */
    Tl *t = (Tl *)data;
    switch (opcode) {
    case EVT_TITLE:
        if (args[0].s) {
            char *p;
            snprintf(t->title, sizeof(t->title), "%s", args[0].s);
            /* o protocolo linha-a-linha: \n/\r dentro de título é fim de
             * mundo falso (revisão 3-a) — sanitiza na entrada */
            for (p = t->title; *p; p++)
                if (*p == '\n' || *p == '\r') {
                    *p = ' ';
                }
        }
        break;
    case EVT_APP_ID:
        if (args[0].s) {
            char *p;
            snprintf(t->app_id, sizeof(t->app_id), "%s", args[0].s);
            for (p = t->app_id; *p; p++)
                if (*p == '\n' || *p == '\r') {
                    *p = ' ';
                }
        }
        break;
    case EVT_STATE: {
        struct wl_array *arr = (struct wl_array *)args[0].a;
        uint32_t *st;
        t->flags = 0;
        wl_array_for_each(st, arr) {
            if (*st == 0) t->flags |= F_MAXIMIZED;
            else if (*st == 1) t->flags |= F_MINIMIZED;
            else if (*st == 2) { t->flags |= F_ACTIVATED; mru_promote(t); }
            else if (*st == 3) t->flags |= F_FULLSCREEN;
        }
        break;
    }
    case EVT_DONE:
        break;
    case EVT_CLOSED:
        t->dead = 1;
        mru_remove(t);
        break;
    default:
        break;
    }
    return 0;
}

/* varredura pós-dispatch: destruir os proxies marcados mortos FORA do
 * callback (destruir proxy dentro do próprio dispatch é terreno frágil).
 * O Tl é liberado; a compactação troca PONTEIROS no array — o objeto nunca
 * se move (dispatcher_data e mru[] continuam válidos). */
static void sweep_dead(void)
{
    int i;
    for (i = 0; i < n_wins; ) {
        Tl *t = wins[i];
        if (t->dead) {
            if (t->proxy) {
                wl_proxy_destroy(t->proxy);
            }
            free(t);
            wins[i] = wins[n_wins - 1];
            n_wins--;
        } else {
            i++;
        }
    }
}

/* ── dispatcher do manager (nova janela anunciada) ───────────────────── */
static int mgr_dispatcher(const void *data, void *target, uint32_t opcode,
                          const struct wl_message *msg, union wl_argument *args)
{
    (void)data; (void)target; (void)msg;
    if (opcode != 0) {
        /* finished (1): o gerente morreu (ex.: labwc encerrando) — o
         * restante da sessão cai junto; log honesto e segue servindo o
         * estado estático até o supervisor reiniciar tudo */
        fprintf(stderr, "craft-toplevel: manager anunciou finished\n");
        return 0;
    }
    if (n_wins >= MAX_WIN) {
        /* teto: o demarshal JÁ criou o proxy do new_id — destruí-lo aqui
         * é a única forma de não vazar (a revisão 3-a flagrou) */
        wl_proxy_destroy((struct wl_proxy *)args[0].o);
        return 0;
    }
    Tl *t = calloc(1, sizeof(*t));
    if (!t) {
        wl_proxy_destroy((struct wl_proxy *)args[0].o);
        return 0;
    }
    wins[n_wins++] = t;
    /* new_id em EVENTO, no cliente: o demarshal já CRIOU o proxy (usando o
     * tipo do array acima) e o entrega em .o — .n seria ler 32 bits do
     * ponteiro (o gcc flagrou exatamente isso) */
    t->proxy = (struct wl_proxy *)args[0].o;
    t->id = next_id++;
    t->rank = n_mru;
    if (n_mru < MAX_MRU) {
        mru[n_mru++] = t;
    }
    /* dispatcher_data = a janela (o dispatcher a recebe no 1º parâmetro) */
    wl_proxy_add_dispatcher(t->proxy, tl_dispatcher, t, NULL);
    return 0;
}

/* ── registry (bind do manager + do seat que o activate exige) ───────── */
static int registry_dispatcher(const void *data, void *target,
                               uint32_t opcode, const struct wl_message *msg,
                               union wl_argument *args)
{
    (void)data; (void)msg;
    if (opcode != 0) {
        return 0; /* global_remove: nada ouriveado aqui */
    }
    uint32_t name = args[0].u;
    const char *iface = args[1].s;
    uint32_t version = args[2].u;
    struct wl_proxy *reg = (struct wl_proxy *)target;

    if (strcmp(iface, mgr_iface.name) == 0) {
        uint32_t v = version < 3 ? version : 3;
        struct wl_proxy *mgr = wl_proxy_marshal_constructor(
            reg, 0 /* WL_REGISTRY_BIND */, &mgr_iface,
            name, mgr_iface.name, v);
        if (!mgr) {
            fprintf(stderr, "craft-toplevel: bind do manager falhou\n");
            return 0;
        }
        mgr_bound = 1;
        wl_proxy_add_dispatcher(mgr, mgr_dispatcher, NULL, NULL);
    } else if (strcmp(iface, "wl_seat") == 0) {
        /* o request activate (opcode 4) EXIGE um wl_seat — o XML oficial:
         * <arg name="seat" type="object" interface="wl_seat"/> */
        seat_proxy = wl_proxy_marshal_constructor(
            reg, 0, &wl_seat_interface, name, "wl_seat", 1);
        if (seat_proxy) {
            /* capabilities chega e ninguém a lê — dispatcher no-op para o
             * evento nunca bater em proxy sem ouvinte */
            wl_proxy_add_dispatcher(seat_proxy, noop_dispatcher, NULL, NULL);
        }
    }
    return 0;
}

/* ── socket UNIX da sessão ───────────────────────────────────────────── */
#define MAX_CLIENTS 8
#define RBUF 8192

typedef struct {
    int fd;
    size_t len;
    char buf[RBUF];
} Client;

static Client clients[MAX_CLIENTS];

static void reply(Client *c, const char *s)
{
    size_t n = strlen(s);
    size_t done = 0;
    while (done < n) {
        ssize_t w = write(c->fd, s + done, n - done);
        if (w <= 0) {
            if (w < 0 && (errno == EINTR)) {
                continue;
            }
            if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                /* cliente não-block travado no read: corta-o em vez de
                 * pendurar o daemon inteiro (revisão 3-a) */
                close(c->fd);
                c->fd = -1;
            }
            return; /* EPIPE etc — o próximo poll limpa o cliente */
        }
        done += (size_t)w;
    }
}

static Tl *by_id(uint32_t id)
{
    int i;
    for (i = 0; i < n_wins; i++)
        if (wins[i]->id == id && !wins[i]->dead)
            return wins[i];
    return NULL;
}

static Tl *focused_win(void)
{
    int i;
    for (i = 0; i < n_mru; i++)
        if (mru[i]->flags & F_ACTIVATED && !mru[i]->dead)
            return mru[i];
    return NULL;
}

static void activate(Tl *t)
{
    /* a ordem É a lei: unset_minimized (3) ANTES do activate (4) —
     * restaurar-minimizada por comando do protocolo, não hipótese */
    wl_proxy_marshal(t->proxy, TL_UNSET_MINIMIZED);
    wl_proxy_marshal(t->proxy, TL_ACTIVATE, seat_proxy);
    t->flags &= ~(uint32_t)F_MINIMIZED; /* estado otimista coerente */
    mru_optimistic_focus(t);
}

static void serve_list(Client *c)
{
    char line[1024];
    int i;
    for (i = 0; i < n_mru; i++) {
        Tl *t = mru[i];
        if (t->dead) {
            continue;
        }
        snprintf(line, sizeof(line), "W|%u|%u|%d|%s|%s\n",
                 t->id, t->flags, t->rank, t->app_id, t->title);
        reply(c, line);
    }
    Tl *f = focused_win();
    snprintf(line, sizeof(line), "OK|%u\n", f ? f->id : 0u);
    reply(c, line);
}

static void serve_cycle(Client *c)
{
    if (n_mru == 0) {
        reply(c, "ERR|no-windows\n");
        return;
    }
    Tl *f = focused_win();
    int i = -1;
    if (f) {
        int k;
        for (k = 0; k < n_mru; k++)
            if (mru[k] == f) {
                i = k;
                break;
            }
    }
    Tl *t = (i >= 0) ? mru[(i + 1) % n_mru] : mru[0];
    if (t != f && seat_proxy) {
        activate(t);
    }
    char line[768];
    snprintf(line, sizeof(line), "OK|%u|%s|%s\n", t->id, t->app_id, t->title);
    reply(c, line);
}

static void handle_line(Client *c, char *ln)
{
    while (*ln == ' ' || *ln == '\t') {
        ln++;
    }
    if (strncmp(ln, "PING", 4) == 0) {
        reply(c, "PONG\n");
    } else if (strncmp(ln, "LIST", 4) == 0) {
        serve_list(c);
    } else if (strncmp(ln, "CYCLE", 5) == 0) {
        serve_cycle(c);
    } else if (strncmp(ln, "ACT ", 4) == 0) {
        Tl *t = by_id((uint32_t)strtoul(ln + 4, NULL, 10));
        if (t && seat_proxy) {
            activate(t);
            reply(c, "OK\n");
        } else {
            reply(c, t ? "ERR|no-seat\n" : "ERR|no-window\n");
        }
    } else if (strncmp(ln, "CLOSE ", 6) == 0) {
        Tl *t = by_id((uint32_t)strtoul(ln + 6, NULL, 10));
        if (t) {
            wl_proxy_marshal(t->proxy, TL_CLOSE);
            reply(c, "OK\n");
        } else {
            reply(c, "ERR|no-window\n");
        }
    } else if (ln[0] != '\0') {
        reply(c, "ERR|unknown\n");
    }
}

static void client_read(Client *c)
{
    if (c->len >= sizeof(c->buf)) {
        c->len = 0; /* linha monstruosa: descarta, o cliente vive */
    }
    ssize_t r = read(c->fd, c->buf + c->len, sizeof(c->buf) - c->len);
    if (r <= 0) {
        if (r < 0 && errno == EINTR) {
            return;
        }
        close(c->fd);
        c->fd = -1;
        return;
    }
    c->len += (size_t)r;
    size_t start = 0;
    size_t i;
    for (i = 0; i < c->len; i++) {
        if (c->buf[i] == '\n') {
            c->buf[i] = '\0';
            if (i > start && c->buf[i - 1] == '\r') {
                c->buf[i - 1] = '\0';
            }
            handle_line(c, c->buf + start);
            start = i + 1;
        }
    }
    if (start > 0) {
        memmove(c->buf, c->buf + start, c->len - start);
        c->len -= start;
    }
}

static const char *sock_path(void)
{
    static char path[256];
    const char *xdg = getenv("XDG_RUNTIME_DIR");
    if (!xdg || !*xdg) {
        return NULL;
    }
    snprintf(path, sizeof(path), "%s/elite", xdg);
    return path;
}

int main(void)
{
    signal(SIGPIPE, SIG_IGN);
    setvbuf(stderr, NULL, _IOLBF, 0);

    if (!getenv("WAYLAND_DISPLAY")) {
        fprintf(stderr, "craft-toplevel: sem WAYLAND_DISPLAY — saindo "
                        "(o daemon só vive na sessão)\n");
        return 0;
    }
    disp = wl_display_connect(NULL);
    if (!disp) {
        fprintf(stderr, "craft-toplevel: wl_display_connect falhou (%s)\n",
                strerror(errno));
        return 1;
    }
    /* get_registry pela API REAL da biblioteca — a build #117 ensinou com
     * o rig: marshal manual do get_registry com opcode 0 mandou um SYNC
     * (0=sync, 1=get_registry), o callback@2 do compositor chegou como
     * "message too short" no meu pseudo-registry e o daemon saiu honesto
     * (25 exits no bars.log — o gate travou o release, como manda a casa) */
    struct wl_proxy *reg =
        (struct wl_proxy *)wl_display_get_registry(disp);
    if (!reg) {
        fprintf(stderr, "craft-toplevel: registry falhou\n");
        return 1;
    }
    wl_proxy_add_dispatcher(reg, registry_dispatcher, NULL, NULL);

    /* roundtrip 1: o registry anuncia globals (manager, seat); roundtrip 2:
     * globals anunciados por eventos pós-bind também entram */
    wl_display_roundtrip(disp);
    wl_display_roundtrip(disp);
    if (!mgr_bound) {
        fprintf(stderr, "craft-toplevel: este compositor não fala "
                        "zwlr_foreign_toplevel_management_v1 — saindo\n");
        return 1;
    }
    if (!seat_proxy) {
        fprintf(stderr, "craft-toplevel: sem wl_seat — activate indisponível\n");
        return 1;
    }

    /* ── socket: segunda instância é no-op (socket vivo = já servindo) ── */
    const char *dir = sock_path();
    if (!dir) {
        fprintf(stderr, "craft-toplevel: sem XDG_RUNTIME_DIR — saindo\n");
        return 1;
    }
    mkdir(dir, 0700);
    static char path[300];
    snprintf(path, sizeof(path), "%s/toplevel.sock", dir);

    /* fechadura de arranque (revisão 3-a): a janela entre o probe e o bind
     * deixa dois daemons nascerem juntos — o flock é a verdade atômica e
     * morre com o processo (sem limpeza, sem arquivo-órfão com significado) */
    static char lockp[320];
    snprintf(lockp, sizeof(lockp), "%s.lock", path);
    int lk = open(lockp, O_CREAT | O_RDWR, 0600);
    if (lk < 0 || flock(lk, LOCK_EX | LOCK_NB) != 0) {
        fprintf(stderr, "craft-toplevel: fechadura ocupada — outro daemon "
                        "já está nascendo — no-op\n");
        if (lk >= 0) {
            close(lk);
        }
        return 0;
    }

    struct sockaddr_un sa;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", path);

    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
        if (connect(probe, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
            close(probe);
            fprintf(stderr, "craft-toplevel: daemon já vivo — no-op\n");
            return 0;
        }
        close(probe);
    }
    unlink(path);

    int ls = socket(AF_UNIX, SOCK_STREAM, 0);
    if (ls < 0 || bind(ls, (struct sockaddr *)&sa, sizeof(sa)) < 0 ||
        listen(ls, 4) < 0) {
        fprintf(stderr, "craft-toplevel: socket %s falhou (%s)\n",
                path, strerror(errno));
        return 1;
    }

    int i;
    for (i = 0; i < MAX_CLIENTS; i++) {
        clients[i].fd = -1;
    }
    fprintf(stderr, "craft-toplevel: vivo — %s (%d janela(s) na sessão)\n",
            path, n_wins);

    for (;;) {
        struct pollfd pfds[2 + MAX_CLIENTS];
        pfds[0].fd = wl_display_get_fd(disp);
        pfds[0].events = POLLIN;
        pfds[1].fd = ls;
        pfds[1].events = POLLIN;
        int n = 2;
        for (i = 0; i < MAX_CLIENTS; i++) {
            if (clients[i].fd >= 0) {
                pfds[n].fd = clients[i].fd;
                pfds[n].events = POLLIN;
                pfds[n].revents = 0;
                n++;
            }
        }
        int pr = poll(pfds, (nfds_t)n, -1);
        if (pr < 0) {
            if (errno == EINTR) {
                continue; /* revents podem estar sujos — sem leitura */
            }
            break;
        }
        if (pfds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
            if (wl_display_dispatch(disp) < 0) {
                fprintf(stderr, "craft-toplevel: compositor perdeu a "
                                "conexão — o supervisor reinicia\n");
                return 1;
            }
        }
        if (pfds[1].revents & POLLIN) {
            int fd = accept(ls, NULL, NULL);
            if (fd >= 0) {
                /* não-block: um cliente que não lê LIST nenhum não pode
                 * congelar o daemon no write (revisão 3-a) */
                fcntl(fd, F_SETFL, O_NONBLOCK);
                for (i = 0; i < MAX_CLIENTS; i++) {
                    if (clients[i].fd < 0) {
                        clients[i].fd = fd;
                        clients[i].len = 0;
                        break;
                    }
                }
                if (i == MAX_CLIENTS) {
                    close(fd);
                }
            }
        }
        for (i = 2; i < n; i++) {
            if (pfds[i].revents & (POLLIN | POLLHUP | POLLERR)) {
                int k;
                for (k = 0; k < MAX_CLIENTS; k++) {
                    if (clients[k].fd == pfds[i].fd) {
                        client_read(&clients[k]);
                        break;
                    }
                }
            }
        }
        sweep_dead();
        wl_display_flush(disp);
    }
    return 1;
}
