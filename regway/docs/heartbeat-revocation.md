# Heartbeat, audit и отзыв токена (RustDesk 1.5.0 + rustdesk-api lejianwen)

Код: rustdesk тег 1.5.0 (`fada664`), rustdesk-api `lejianwen/rustdesk-api` master `c5687e1` (29.09.2025).

## (а) Heartbeat — `src/hbbs_http/sync.rs`
* Поток `start_hbbs_sync_async()` запускается из `rendezvous_mediator.rs:281`, то есть в **серверном процессе управляемой стороны** (`--server`), а не в GUI.
* Таймер тикает каждые `TIME_CONN = 3 с`. Heartbeat (`POST {api}/api/heartbeat`, тело `{id, uuid, ver, conns?, modified_at}`) отправляется:
  * при наличии входящих сеансов (`conns` не пуст) — **на каждом тике, т.е. каждые 3 с**;
  * без сеансов — не чаще `TIME_HEARTBEAT = 15 с`.
* Sysinfo (`/api/sysinfo`) — при первом запуске, смене id/username, повтор не раньше `UPLOAD_SYSINFO_TIMEOUT = 120 с`.
* Реакция на ответ (upstream): ответ — JSON; ключи `sysinfo` (перезалить sysinfo), `disconnect: [conn_id…]` (закрыть эти входящие сеансы: «Closed manually by web console», `connection.rs:1067`, port-forward — `:1376`), `modified_at` + `strategy` (применить опции). **HTTP-статус upstream игнорирует** (`post_request` отдаёт только тело), ошибки сети логируются и пропускаются. Токен в heartbeat upstream **не отправляет**.
* lejianwen `/api/heartbeat` (`http/controller/api/index.go`) **без авторизации**, всегда `200 {}`: обновляет `last_online_time` (не чаще раза в 30 с), `disconnect` не возвращает никогда.

## (б) `type` в audit conn — `src/server/connection.rs:1900–1924`
Подтверждено для 1.5.0: `0` — управление (Remote), `1` — передача файлов, `2` — port forward, `3` — просмотр камеры, `4` — терминал. Порядок проверок: file_transfer → port_forward → view_camera → terminal → иначе 0.

## (в) Кто шлёт `/api/audit/conn`
**Управляемая (принимающая) сторона**: `Connection` в `src/server/connection.rs` (входящее соединение). Последовательность: `action:"new"` с `ip` после рукопожатия (`:1514`), запись без action с `peer:[id, name]`, `type`, `primary_auth`/`two_factor` после авторизации (`:1924`), `action:"close"` при закрытии (`:1227`). В каждой записи `id`, `uuid` устройства, `conn_id`, `session_id`, `nonce`. URL `{api}/api/audit/conn`, токен не прикладывается. lejianwen хранит это в `model.AuditConn` (`ConnId`, `PeerId`, `FromPeer`, `Type`, `CloseTime`).

## Наш патч (apply-branding.sh, раздел 2d)
1. Heartbeat прикладывает `Authorization: Bearer <access_token>`, если токен есть в `LocalConfig` **серверного процесса**.
2. Ответ читается через `crate::post_request_with_status` (upstream-функция, те же правила TCP-фолбэка).
3. Реакция:
   | Ответ | Действие |
   |---|---|
   | HTTP **401** и токен был отправлен | счётчик +1; при **2 подряд** → `regway_revoke_sessions()`: все `Connection::alive_conns()` в канал `disconnect` (закрываются все входящие сеансы: управление, файлы, port forward, камера, терминал), `access_token` и `user_info` стираются |
   | 2xx | счётчик = 0, обычная обработка (`disconnect`, `strategy`, …) |
   | 401 без токена, 403, прочие 4xx, 5xx, таймаут, DNS, TLS-ошибка, connection refused | **ничего не рвём**, счётчик не меняется |
   lejianwen на отозванный/неверный/отключённый токен отвечает `401 {"error":"Unauthorized"}` (`http/middleware/rustauth.go`), 403 и «invalid token» в теле не используются — реагируем только на статус 401.
4. Порог: с активными сеансами heartbeat идёт каждые 3 с → разрыв через **≈3–6 с + RTT** после первого 401 (два тика). Ускорять `TIME_HEARTBEAT` (15 с) не нужно: он действует только без сеансов, когда рвать нечего. Требование «2 подряд» страхует от одиночного 401 при выкатке nginx/API.

### Ограничения патча (важно)
* **Сам по себе со штатным lejianwen не сработает**: `/api/heartbeat` у них без `RustAuth` и всегда 200. Нужна правка нашего форка API: если пришёл `Authorization`, проверять токен как в `RustAuth` и на невалидный отвечать 401 (без заголовка — как сейчас, 200). Пример:
  ```go
  // http/controller/api/index.go, начало Heartbeat
  if h := c.GetHeader("Authorization"); len(h) > 7 {
      if u, _ := service.AllService.UserService.InfoByAccessToken(h[7:]); u.Id == 0 ||
          !service.AllService.UserService.CheckUserEnable(u) {
          c.JSON(401, gin.H{"error": "Unauthorized"}); return
      }
  }
  ```
* Токен берётся из LocalConfig **серверного** процесса. На macOS (`--server` из LaunchAgent от имени пользователя) и в портативном режиме Windows это тот же конфиг, что у GUI. В **установленном Windows** `--server` работает от SYSTEM со своим профилем конфигурации → токена там обычно нет, патч бездействует (безопасно, но бесполезно).
* Патч отзывает **собственный токен управляемого устройства**. С `MUST_LOGIN=Y` (форк lejianwen/rustdesk-server) логин обязателен для **управляющего** (токен уходит в `PunchHoleRequest`), управляемый часто не залогинен. Отзыв учётки техника этим патчем входящие сеансы на клиентских машинах **не рвёт**.

## Рекомендуемый способ рвать сеансы отозванного техника
**`disconnect` в ответе heartbeat (уже поддерживается клиентом 1.5.0, патч клиента не нужен).** Форк API при heartbeat управляемого устройства берёт `conns` из тела, по `AuditConn` (`PeerId` = id устройства, `ConnId`, `FromPeer` = id техника, `CloseTime = 0`) находит сеансы, где `FromPeer` принадлежит отозванному/отключённому пользователю (связь peer↔user — по токену, с которым техник логинился/делал sysinfo), и возвращает `{"disconnect":[conn_id…]}`. Задержка ≤ 3 с + RTT, работает на всех ОС, не зависит от того, залогинена ли управляемая сторона, и не обходится модификацией клиента техника.

## Альтернатива: разрыв через hbbs/hbbr форка
* **hbbs** участвует только в установке соединения (punch hole / relay request). С `MUST_LOGIN=Y` он уже не пустит отозванный токен в **новые** сеансы, но **текущие** не видит.
* **hbbr** видит только relay-сеансы: можно закрыть пару сокетов по UUID сеанса (связать с токеном при `RequestRelay`). Прямые P2P/LAN-сеансы идут мимо hbbr, поэтому надёжно только при принудительном relay (на клиенте нет штатной жёсткой опции, патч `force-always-relay`). Плюс: не зависит от клиента. Минусы: доработка Rust-сервера, прямые соединения, больше трафика через VPS.
* Итог: основной механизм — `disconnect` через API; MUST_LOGIN в hbbs — блокировка новых сеансов; наш 401-патч — дополнительная защита для залогиненных управляемых устройств; hbbr — только если обязателен relay.
