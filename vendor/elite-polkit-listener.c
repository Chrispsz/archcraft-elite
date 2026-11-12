/*
 * ═══════════════════════════════════════════════════════════════════════════
 * Archcraft ELITE · elite-polkit-listener (E103 — O POLKIT SOB DEMANDA)
 * ═══════════════════════════════════════════════════════════════════════════
 * A diretriz do dono: "subir o prompt de privilégios root APENAS quando uma
 * aplicação (como GParted ou Pacman) solicitar, encerrando a execução logo
 * em seguida para manter consumo de RAM nulo em idle".
 *
 * A PERÍCIA NO FONTE DO POLKIT (polkitbackendinteractiveauthority.c, main):
 *   · o polkitd REJEITA um segundo agente por sessão ("An authentication
 *     agent already exists for the given subject") — dois agentes = duas
 *     caixas de senha por pedido (a lei E58/E95 da casa era sintoma real);
 *   · o polkitd NUNCA D-Bus ativa agentes — o agente se REGISTRA nele
 *     (RegisterAuthenticationAgent); sem registro, o pedido de auth volta
 *     com erro. Não existe "agente dormente ativável".
 * A ARQUITETURA CORRETA é a de dois corpos (o mesmo desenho do GNOME, que
 * registra o listener dentro do gnome-shell):
 *   · O LISTENER (este binário) — a única coisa sempre viva: um GDBus loop
 *     que REGISTRA o agente da sessão e FICA ESCUTANDO (idle ≈ 1–2 MB,
 *     sem Qt, sem GTK — nada de janela esperando);
 *   · O DIÁLOGO (zenity, GTK) — só existe DURANTE o desafio: cada
 *     BeginAuthentication sobe UM diálogo, a senha volta pelo protocolo do
 *     helper (PolkitAgentSession → polkit-agent-helper-1), e o diálogo
 *     morre com o desafio. Errado o pedido = novo diálogo (até 3 tentativas).
 * Fallback honesto da casa: sem zenity ou sem libpolkit-agent este binário
 * sai 1 no arranque — e o craft-bars elege o lxqt-policykit-agent da
 * antigamente (a fila E58 continua sendo a rede; o trono só muda de rei).
 *
 * Base do padrão GObject: polkitagenttextlistener.c (LGPL 2.1, David
 * Zeuthen, Red Hat) — os vfuncs do PolkitAgentListener seguem a mesma
 * gramática; o diálogo TTY virou diálogo zenity da casa.
 * Build: gcc -O2 -Wall -Wextra -s -o elite-polkit-listener \
 *            elite-polkit-listener.c $(pkg-config --libs polkit-agent-1 gobject-2.0)
 * ═══════════════════════════════════════════════════════════════════════════
 */

#define GLIB_DISABLE_DEPRECATION_WARNINGS

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <pwd.h>

#include <polkitagent/polkitagent.h>
#include <polkit/polkit.h>

/* ── o objeto ──────────────────────────────────────────────────────────── */

struct _ElitePolkitListener
{
  PolkitAgentListener parent_instance;

  GSimpleAsyncResult *simple;
  PolkitAgentSession *active_session;
  GCancellable       *cancellable;
  gulong              cancel_id;

  GSubprocess        *zenity;          /* o diálogo vivo (se houver)      */
  GCancellable       *zenity_cancel;   /* cancela a leitura do stdout     */
  gchar              *password;        /* senha coletada (consumida uma vez) */
  guint               attempts;        /* tentativas de diálogo nesta auth */
  gchar              *message;         /* texto do desafio (para re-diálogo) */
  gchar              *action_id;
};

typedef struct _ElitePolkitListener ElitePolkitListener;

typedef struct
{
  PolkitAgentListenerClass parent_class;
} ElitePolkitListenerClass;

/* os macros do tipo (a GLib moderna não os gera no G_DEFINE_TYPE) */
#define ELITE_TYPE_POLKIT_LISTENER (elite_polkit_listener_get_type ())
#define ELITE_POLKIT_LISTENER(obj) (G_TYPE_CHECK_INSTANCE_CAST ((obj), \
                                   ELITE_TYPE_POLKIT_LISTENER, ElitePolkitListener))

G_DEFINE_TYPE (ElitePolkitListener, elite_polkit_listener, POLKIT_AGENT_TYPE_LISTENER)

#define MAX_ATTEMPTS 3

/* ── o log da casa (stderr = bars.log pelo craft-bars) ─────────────────── */
static void
elog (const gchar *fmt, ...)
{
  va_list ap;
  GString *s = g_string_new (NULL);
  va_start (ap, fmt);
  g_string_vprintf (s, fmt, ap);
  va_end (ap);
  fprintf (stderr, "elite-polkit-listener: %s\n", s->str);
  g_string_free (s, TRUE);
}

static void elite_polkit_listener_cancel (ElitePolkitListener *listener);

/* ── identidade escolhida: a do PRÓPRIO usuário primeiro (o dono digita a
 *    senha DELE; a lista do polkit pode trazer root/admin) ──────────────── */
static PolkitIdentity *
choose_identity (GList *identities)
{
  GList *l;
  uid_t me = getuid ();
  for (l = identities; l != NULL; l = l->next)
    {
      if (POLKIT_IS_UNIX_USER (POLKIT_IDENTITY (l->data)) &&
          (uid_t) polkit_unix_user_get_uid (POLKIT_UNIX_USER (l->data)) == me)
        return POLKIT_IDENTITY (l->data);
    }
  return identities != NULL ? POLKIT_IDENTITY (identities->data) : NULL;
}

/* ── o diálogo zenity (async — a main loop nunca trava) ────────────────── */

static void zenity_done (GObject *source, GAsyncResult *res, gpointer user_data);

static void
spawn_dialog (ElitePolkitListener *listener)
{
  GError *err = NULL;
  gchar  *title;
  const gchar *msg = listener->message ? listener->message : "Autenticação requerida";

  title = g_strdup_printf ("Elite · Autenticação (%d/%d)",
                           listener->attempts + 1, MAX_ATTEMPTS);

  listener->attempts += 1;
  g_clear_object (&listener->zenity_cancel);
  listener->zenity_cancel = g_cancellable_new ();

  listener->zenity = g_subprocess_newv ((const gchar * const[]) {
      "zenity", "--password", "--title", title, "--text", msg,
      "--ok-label", "Autenticar", "--cancel-label", "Cancelar", NULL },
      G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_SILENCE,
      &err);
  g_free (title);

  if (listener->zenity == NULL)
    {
      elog ("zenity não nasceu (%s) — cancelando o desafio", err ? err->message : "?");
      g_clear_error (&err);
      if (listener->active_session != NULL)
        polkit_agent_session_cancel (listener->active_session);
      return;
    }

  elog ("diálogo da senha aberto (tentativa %d)", listener->attempts);

  g_subprocess_communicate_utf8_async (listener->zenity,
                                       NULL,               /* stdin fechado */
                                       listener->zenity_cancel,
                                       zenity_done,
                                       g_object_ref (listener));
}

static void
zenity_done (GObject *source, GAsyncResult *res, gpointer user_data)
{
  ElitePolkitListener *listener = ELITE_POLKIT_LISTENER (user_data);
  GSubprocess *sub = G_SUBPROCESS (source);
  gchar *stdout_str = NULL;
  GError *err = NULL;
  gboolean ok;
  gboolean cancelado = FALSE;
  gboolean rc_ok = FALSE;

  ok = g_subprocess_communicate_utf8_finish (sub, res, &stdout_str, NULL, &err);
  if (!ok)
    {
      /* cancelado de fora (cancel_authentication) — silêncio honesto */
      if (err != NULL && g_error_matches (err, G_IO_ERROR, G_IO_ERROR_CANCELLED))
        {
          cancelado = TRUE;
        }
      else
        {
          elog ("diálogo morreu sem resposta (%s)", err ? err->message : "?");
        }
      g_clear_error (&err);
    }
  else
    {
      /* rc ≠ 0 = o usuário cancelou (zenity sai 1 no Cancelar/ESC) */
      rc_ok = g_subprocess_get_successful (sub);
      if (!rc_ok)
        {
          elog ("diálogo cancelado pelo dono (tentativa %d)", listener->attempts);
          g_free (stdout_str);
          stdout_str = NULL;
          cancelado = TRUE;
        }
    }

  listener->zenity = NULL;              /* o sub mora aqui até o fim da leitura */
  g_clear_object (&sub);

  g_object_unref (listener);            /* devolve a ref do user_data */

  if (cancelado)
    {
      if (listener->active_session != NULL)
        polkit_agent_session_cancel (listener->active_session);
      return;
    }

  /* o stdout do zenity --password é a senha com \n final */
  if (stdout_str != NULL)
    {
      gsize len = strlen (stdout_str);
      while (len > 0 && (stdout_str[len - 1] == '\n' || stdout_str[len - 1] == '\r'))
        stdout_str[--len] = '\0';
    }

  g_free (listener->password);
  listener->password = stdout_str;      /* NULL se o dono deixou vazio */

  if (listener->password == NULL || listener->password[0] == '\0')
    {
      elog ("diálogo fechado sem senha — cancelando o desafio");
      g_clear_pointer (&listener->password, g_free);
      if (listener->active_session != NULL)
        polkit_agent_session_cancel (listener->active_session);
      return;
    }

  /* a senha pode chegar ANTES do primeiro request do helper (o diálogo é
   * rápido, o PAM nem sempre) — o on_request entrega quando pedir */
  elog ("senha coletada — aguardando o helper pedir");
}

/* ── os sinais do PolkitAgentSession ───────────────────────────────────── */

static void
on_request (PolkitAgentSession *session,
            const gchar        *request,
            gboolean            echo_on,
            gpointer            user_data)
{
  ElitePolkitListener *listener = ELITE_POLKIT_LISTENER (user_data);

  (void) echo_on;

  if (listener->password == NULL)
    {
      /* o helper pediu e o diálogo ainda não respondeu — ele responde
       * quando o zenity_done entregar (o pending de cima) */
      if (listener->zenity == NULL && listener->attempts < MAX_ATTEMPTS)
        {
          elog ("helper pediu ('%s') sem diálogo vivo — abrindo outro", request);
          spawn_dialog (listener);
        }
      return;
    }

  polkit_agent_session_response (session, listener->password);
  memset (listener->password, 0, strlen (listener->password));
  g_free (listener->password);
  listener->password = NULL;   /* uma senha serve UM request; errada = outro diálogo */
}

static void
on_completed (PolkitAgentSession *session,
              gboolean            gained_authorization,
              gpointer            user_data)
{
  ElitePolkitListener *listener = ELITE_POLKIT_LISTENER (user_data);

  (void) session;

  elog ("desafio concluído (%s)", gained_authorization ? "autorizado" : "falhou");

  if (listener->simple != NULL)
    {
      g_simple_async_result_complete_in_idle (listener->simple);
      g_object_unref (listener->simple);
      listener->simple = NULL;
    }
  g_object_unref (listener->active_session);
  listener->active_session = NULL;
  g_clear_pointer (&listener->password, g_free);   /* a senha morre com o desafio */
  if (listener->cancel_id != 0)
    {
      g_cancellable_disconnect (listener->cancellable, listener->cancel_id);
      listener->cancel_id = 0;
    }
  g_clear_object (&listener->cancellable);
}

static void
on_show_error (PolkitAgentSession *session, const gchar *text, gpointer user_data)
{
  (void) session;
  (void) user_data;
  elog ("polkit: erro — %s", text);
}

static void
on_show_info (PolkitAgentSession *session, const gchar *text, gpointer user_data)
{
  (void) session;
  (void) user_data;
  elog ("polkit: info — %s", text);
}

static void
on_cancelled (GCancellable *cancellable, gpointer user_data)
{
  ElitePolkitListener *listener = ELITE_POLKIT_LISTENER (user_data);

  (void) cancellable;
  elog ("desafio cancelado pela autoridade");
  elite_polkit_listener_cancel (listener);
}

/* ── os vfuncs do listener ─────────────────────────────────────────────── */

static void
elite_polkit_listener_initiate_authentication (PolkitAgentListener  *_listener,
                                               const gchar          *action_id,
                                               const gchar          *message,
                                               const gchar          *icon_name,
                                               PolkitDetails        *details,
                                               const gchar          *cookie,
                                               GList                *identities,
                                               GCancellable         *cancellable,
                                               GAsyncReadyCallback   callback,
                                               gpointer              user_data)
{
  ElitePolkitListener *listener = ELITE_POLKIT_LISTENER (_listener);
  PolkitIdentity *identity;
  GSimpleAsyncResult *simple;

  (void) icon_name;
  (void) details;

  simple = g_simple_async_result_new (G_OBJECT (listener),
                                      callback,
                                      user_data,
                                      elite_polkit_listener_initiate_authentication);

  if (listener->active_session != NULL)
    {
      g_simple_async_result_set_error (simple, POLKIT_ERROR, POLKIT_ERROR_FAILED,
                                       "An authentication session is already underway.");
      g_simple_async_result_complete_in_idle (simple);
      g_object_unref (simple);
      return;
    }

  identity = choose_identity (identities);
  if (identity == NULL)
    {
      g_simple_async_result_set_error (simple, POLKIT_ERROR, POLKIT_ERROR_FAILED,
                                       "No identity to authenticate as.");
      g_simple_async_result_complete_in_idle (simple);
      g_object_unref (simple);
      return;
    }

  listener->attempts = 0;
  g_free (listener->message);
  listener->message = g_strdup (message ? message : "Autenticação requerida");
  g_free (listener->action_id);
  listener->action_id = g_strdup (action_id ? action_id : "?");

  listener->active_session = polkit_agent_session_new (identity, cookie);
  g_signal_connect (listener->active_session, "completed",
                    G_CALLBACK (on_completed), listener);
  g_signal_connect (listener->active_session, "request",
                    G_CALLBACK (on_request), listener);
  g_signal_connect (listener->active_session, "show-info",
                    G_CALLBACK (on_show_info), listener);
  g_signal_connect (listener->active_session, "show-error",
                    G_CALLBACK (on_show_error), listener);

  listener->simple = simple;
  listener->cancellable = g_object_ref (cancellable);
  listener->cancel_id = g_cancellable_connect (cancellable,
                                               G_CALLBACK (on_cancelled),
                                               listener, NULL);

  elog ("desafio: %s — %s", listener->action_id, listener->message);

  polkit_agent_session_initiate (listener->active_session);
  spawn_dialog (listener);
}

static gboolean
elite_polkit_listener_initiate_authentication_finish (PolkitAgentListener  *_listener,
                                                      GAsyncResult         *res,
                                                      GError              **error)
{
  (void) _listener;
  return g_simple_async_result_propagate_error (G_SIMPLE_ASYNC_RESULT (res), error) == FALSE;
}

static void
elite_polkit_listener_cancel (ElitePolkitListener *listener)
{
  elog ("cancelamento do desafio (a via é o GCancellable da classe)");
  if (listener->zenity != NULL && listener->zenity_cancel != NULL)
    g_cancellable_cancel (listener->zenity_cancel);
  if (listener->active_session != NULL)
    polkit_agent_session_cancel (listener->active_session);
}

/* ── o ciclo GObject ───────────────────────────────────────────────────── */

static void
elite_polkit_listener_finalize (GObject *object)
{
  ElitePolkitListener *listener = ELITE_POLKIT_LISTENER (object);
  if (listener->active_session != NULL)
    g_object_unref (listener->active_session);
  g_clear_object (&listener->zenity);
  g_clear_object (&listener->zenity_cancel);
  g_free (listener->password);
  g_free (listener->message);
  g_free (listener->action_id);
  if (G_OBJECT_CLASS (elite_polkit_listener_parent_class)->finalize != NULL)
    G_OBJECT_CLASS (elite_polkit_listener_parent_class)->finalize (object);
}

static void
elite_polkit_listener_class_init (ElitePolkitListenerClass *klass)
{
  GObjectClass *gobject_class = G_OBJECT_CLASS (klass);
  PolkitAgentListenerClass *listener_class = POLKIT_AGENT_LISTENER_CLASS (klass);

  gobject_class->finalize = elite_polkit_listener_finalize;
  listener_class->initiate_authentication        = elite_polkit_listener_initiate_authentication;
  listener_class->initiate_authentication_finish = elite_polkit_listener_initiate_authentication_finish;
  /* CANCELAMENTO: a classe NÃO tem vfunc cancel — a via é o GCancellable
   * (o on_cancelled abaixo conectado em g_cancellable_connect), o mesmo
   * desenho do polkitagenttextlistener upstream. */
}

static void
elite_polkit_listener_init (ElitePolkitListener *listener)
{
  (void) listener;
}

/* ── o subject do registro (E105 — a prova do dump 195332) ───────────────
 * A API do polkit MUDOU embaixo da casa: o registro moderno é
 *   polkit_agent_listener_register (listener, flags, SUBJECT, object_path,
 *                                   cancellable, error)
 * — o subject virou o 3º argumento OBRIGATÓRIO e o par callback/user_data
 * saiu do protótipo. A chamada da era E103 (callback NULL, object_path no
 * user_data) COMPILOVA CALADA (NULL casa em qualquer ponteiro) e explodia
 * NA HORA no rig: assertion 'POLKIT_IS_SUBJECT (subject)' — o dump 195332
 * fotografou o listener morrendo exit=1 a cada 5s, a sessão inteira SEM
 * agente. A fila do subject, da mais forte para a mais fraca:
 *   1. /proc/self/sessionid — o kernel aponta a sessão logind do processo;
 *   2. XDG_SESSION_ID — o ambiente da sessão.
 * Sem nenhuma das duas → NULL honesto: o main sai 1 com a mensagem
 * clara e o craft-bars elege o fallback da fila (nunca loop cego).
 */
static PolkitSubject *
make_session_subject (void)
{
  FILE *f;
  char buf[32];
  gboolean ok;
  long v;
  const gchar *env;

  f = fopen ("/proc/self/sessionid", "r");
  if (f != NULL)
    {
      ok = (fgets (buf, sizeof buf, f) != NULL);
      fclose (f);
      if (ok)
        {
          v = strtol (buf, NULL, 10);
          if (v > 0 && v < 2147483648L)
            return polkit_unix_session_new (g_strdup_printf ("%ld", v));
        }
    }
  env = g_getenv ("XDG_SESSION_ID");
  if (env != NULL && *env != '\0')
    return polkit_unix_session_new (g_strdup (env));
  return NULL;
}

/* ── main: registra e dorme (o idle de ~1–2 MB) ────────────────────────── */

int
main (int argc, char *argv[])
{
  GError *err = NULL;
  ElitePolkitListener *listener;
  PolkitSubject *subject;
  gpointer reg;
  GMainLoop *loop;

  if (argc == 2 && (strcmp (argv[1], "-h") == 0 || strcmp (argv[1], "--help") == 0))
    {
      fprintf (stdout,
               "uso: elite-polkit-listener — o agente polkit da Elite\n"
               "\n"
               "  Registra o agente de autenticação da SESSÃO e fica em idle (~1–2 MB).\n"
               "  Quando um app (gparted, pkexec, octopi…) pede privilégio, abre UM\n"
               "  diálogo zenity, colhe a senha pelo helper do polkit e encerra o diálogo.\n"
               "  Sem zenity/libpolkit → sai 1 (o craft-bars elege o fallback da fila).\n"
               "  O stderr é o papel da casa (bars.log pelo supervisor).\n");
      return 0;
    }

  if (g_getenv ("ELITE_POLKIT_LISTENER_OFF") != NULL)
    {
      elog ("desligado por env (ELITE_POLKIT_LISTENER_OFF) — a fila elege outro");
      return 1;
    }

  if (g_strcmp0 (g_getenv ("WAYLAND_DISPLAY"), "") == 0 &&
      g_strcmp0 (g_getenv ("DISPLAY"), "") == 0)
    {
      elog ("sem WAYLAND_DISPLAY/DISPLAY — sem sessão gráfica para o diálogo");
      return 1;
    }

  listener = g_object_new (ELITE_TYPE_POLKIT_LISTENER, NULL);

  subject = make_session_subject ();
  if (subject == NULL)
    {
      elog ("sem sessão logind (/proc/self/sessionid vazio, XDG_SESSION_ID ausente) — sem subject honesto para o registro");
      g_object_unref (listener);
      return 1;
    }
  reg = polkit_agent_listener_register (POLKIT_AGENT_LISTENER (listener),
                                        POLKIT_AGENT_REGISTER_FLAGS_NONE,
                                        subject,          /* E105: a sessão EXPLÍCITA (3º arg da API nova) */
                                        "/org/elite/PolicyKit1/AuthenticationAgent",
                                        NULL,
                                        &err);
  g_object_unref (subject);
  if (reg == NULL)
    {
      elog ("registro recusado (%s) — o trono pode estar ocupado (E58/E95) ou a sessão do subject não existe no logind",
            err ? err->message : "?");
      g_clear_error (&err);
      g_object_unref (listener);
      return 1;
    }
  elog ("registrado na sessão — aguardando desafios (idle)");


  loop = g_main_loop_new (NULL, FALSE);
  g_main_loop_run (loop);

  polkit_agent_listener_unregister (reg);
  g_object_unref (listener);
  return 0;
}
