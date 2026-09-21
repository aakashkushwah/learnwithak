# Reverse proxy, explained by running one

Three Spring Boot services behind one nginx, wired up so that every claim about
reverse proxies can be checked with a `curl` rather than taken on faith.

```
docker compose up --build
```

Then pick how you want to go through it:

| | |
|---|---|
| **<http://localhost:8080/>** | **The live demo.** One screen: a topology diagram where request dots animate along the path the response actually took, counters tick per container, and a button makes a replica genuinely start failing. Built for demoing to someone. |
| **<http://localhost:8080/deep-dive.html>** | The long illustrated explainer — seven concepts, diagrams and config, one section each. |
| **`./demo.sh`** | A narrated terminal walkthrough — eight steps, each printing what to say, running the command live, then stating the takeaway. Built for presenting to someone. |
| **This README** | The same ground as `demo.sh`, as copy-pasteable curl commands. |
| **[RESOURCES.md](RESOURCES.md)** | Videos and primary docs to send people afterwards. |

First build takes a couple of minutes (Gradle downloads Spring Boot once).
Afterwards, startup is about 20 seconds.

### Demoing it to someone

Open **<http://localhost:8080/>** and drive it with the four buttons, left to right —
they are ordered as a story:

1. **Send 6 requests** — dots alternate between `orders-a` and `orders-b`. One URL, two machines.
2. **Call the other service** — `/api/users` lights a different box, and `/actuator/health` returns 404 to prove unrouted paths do not exist.
3. **Slow report ×2** — the first dot travels to the backend and takes ~2s; the second **turns around at nginx** and returns in ~2ms. The cache, made visible.
4. **Flood 20 requests** — six green dots get through, fourteen red ones bounce off nginx without ever reaching Java.

Then the closer: **Break orders-b**. That is not a mock — it POSTs to a control
endpoint that makes the replica answer every request with a genuine 503. Press
*Send 6 requests* again and the blocked counter stays at **zero** while every dot
goes to `orders-a`. Press **Revive orders-b** and the label reads *rejoining…*
until `fail_timeout` expires, because nginx really does bench a failed peer for
ten seconds.

The right-hand panel has three tabs for the technical questions that follow:
**Live log** (status, which upstream, cache status, latency per request),
**The config** (the nginx directives behind whatever you just pressed), and
**Headers** (what the Java app sees once nginx has forwarded the client's details).

> The kill switch is demo-only code: a `/_control/fail` endpoint on `orders-service`
> plus two `location` blocks in `nginx.conf` that target one named container instead
> of the pool. Both are commented as such. Delete them and everything else still works.

### Presenting it from a terminal

```bash
./demo.sh              # paused between steps — press Enter to advance
./demo.sh --auto       # no keypresses, 3s between steps, good for screen recording
./demo.sh --step 4     # just the forwarded-headers step
./demo.sh --list       # the eight steps
```

The script refuses to start if the stack is not up, and step 8 stops a replica on
purpose — it restarts it afterwards, including if you Ctrl-C partway through.

---

## The shape of it

```
                      your browser / curl
                              |
              :8080 http      |      :8443 https
                              v
                    +-------------------+
                    |       nginx       |   the reverse proxy
                    +-------------------+
                     /        |         \
                    /         |          \      private docker network
             orders-a     orders-b     users-service
             (Boot)       (Boot)       (Boot)
```

Only nginx publishes ports. The three Java containers publish **nothing** — you cannot
reach them from your machine at all. That is the first and biggest thing a reverse
proxy buys you, and it is enforced here rather than described.

| Path | Goes to | Demonstrates |
|---|---|---|
| `/` | nginx's own disk | static content, no Java involved |
| `/api/orders` | orders-a + orders-b | path routing, load balancing |
| `/api/orders/whoami` | orders pool | the raw view: no forwarded-header handling |
| `/api/orders/limited` | orders pool | rate limiting (5 r/s, burst 5) |
| `/api/users` | users-service | routing to a different application |
| `/api/users/whoami` | users-service | the corrected view: `ForwardedHeaderFilter` |
| `/api/users/slow` | users-service | caching (2s endpoint, 30s cache) |
| `/proxy-health` | nginx itself | a response with no backend at all |
| `/actuator/health` | — | **404**: not routed, therefore not reachable |

---

## The seven steps

Output below is from a real run, so you can tell whether yours is behaving.

### 1. Path routing — one origin, two applications

```bash
curl -s localhost:8080/api/orders | head -c 60
curl -s localhost:8080/api/users  | head -c 60
```

```
{"servedBy":"orders-a","hitsOnThisReplica":1,...
{"servedBy":"users-1","servedAt":...
```

Different `servedBy` means a different Java process answered. The browser cannot tell:
both came from `localhost:8080`. This is also why a front end served from `/` can call
`/api/...` with no CORS configuration — nothing crossed an origin.

Confirm the flip side, that an unrouted path is simply not reachable:

```bash
curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/actuator/health   # 404
```

Both Spring apps serve `/actuator/health` happily. There is no `location` for it, so
from outside it does not exist. A reverse proxy is an allowlist.

### 2. Load balancing — two replicas, one URL

```bash
for i in $(seq 1 6); do curl -s localhost:8080/api/orders \
  | sed -n 's/.*"servedBy":"\([^"]*\)".*/\1/p'; echo; done
```

```
orders-b
orders-a
orders-b
orders-a
orders-b
orders-a
```

Same URL six times, answered by two different containers in turn. Scaling out is a line
in `upstream {}`, not a change any client ever hears about.

> In the first few seconds after `up`, all requests may land on one replica — nginx
> marked the other down while it was still starting and re-tries it after
> `fail_timeout` (10s). Wait a moment and the alternation appears.

### 3. Forwarded headers — the one thing a proxy breaks

Put a proxy in front of an app and the app starts lying: the connection comes from
nginx, so the client IP, scheme and port are all wrong. The two services are configured
on opposite sides of the fix so you can see both.

```bash
curl -s localhost:8080/api/orders/whoami   # forward-headers-strategy: none
curl -s localhost:8080/api/users/whoami    # forward-headers-strategy: framework
```

The raw view (`orders`):

```json
"remoteAddr": "172.22.0.5",                        <- nginx, not you
"requestURL": "http://localhost/api/orders/whoami", <- port 8080 lost
"serverPort": 80,
"isSecure": false
```

...with the truth preserved in the headers nginx attached:

```json
"X-Real-IP": "192.168.65.1",
"X-Forwarded-For": "192.168.65.1",
"X-Forwarded-Proto": "http",
"X-Forwarded-Port": "8080"
```

The corrected view (`users`) reports `remoteAddr: 192.168.65.1` — your actual address —
because `server.forward-headers-strategy: framework` installs Spring's
`ForwardedHeaderFilter`, which rewrites the request from those headers before your
controller runs. The filter also strips them once applied, which is why the users
response shows `(consumed by ForwardedHeaderFilter)`. That is the proof it ran.

> **Trust boundary.** These are ordinary headers and a client can forge them. They are
> safe to believe only because nginx overwrites them at the edge. Never trust
> `X-Forwarded-For` on a server that is also reachable directly.

### 4. TLS termination

```bash
curl -sk https://localhost:8443/api/users/whoami
```

```json
"requestURL": "https://localhost:8443/api/users/whoami",
"scheme": "https",
"isSecure": true
```

nginx decrypted the request and forwarded **plain HTTP** to Spring Boot — yet the app
correctly reports `https`, because `X-Forwarded-Proto` told it so. That is what keeps
redirects and generated links from silently downgrading to `http`.

Not one of the three Java services has a keystore, a cipher list, or a renewal job.
The certificate exists in exactly one place. It is self-signed and generated at
startup by the `cert-init` container, so expect a browser warning once.

### 5. Caching — answering without waking Java

`/api/users/slow` sleeps two seconds on purpose. nginx keeps the reply for 30 seconds.

```bash
for i in 1 2 3; do
  curl -s -o /dev/null -D - -w "time=%{time_total}s " localhost:8080/api/users/slow \
    | grep -i x-cache-status
done
```

```
time=2.018002s  X-Cache-Status: MISS
time=0.002118s  X-Cache-Status: HIT
time=0.001499s  X-Cache-Status: HIT
```

Roughly a thousandfold difference, and calls 2 and 3 never reached the JVM. Watch
`docker compose logs -f users-service` while you run it: the second call logs nothing,
because it never arrived.

You may also see `X-Cache-Status: STALE`. That is not a fault: once the 30-second
window expires, `proxy_cache_use_stale updating` hands you the old copy *immediately*
while refreshing it in the background, so nobody waits two seconds for the refill.

Two directives in the config earn their keep here:

- `proxy_cache_lock on` — when a cache entry expires, one request refills it while the
  rest wait, instead of fifty simultaneous callers stampeding your slowest endpoint.
- `proxy_cache_use_stale` — if the backend is down or erroring, keep serving the last
  good copy rather than an error page.

### 6. Rate limiting — refusing work at the door

```bash
seq 1 20 | xargs -P 20 -I{} curl -s -o /dev/null -w "%{http_code}\n" \
  localhost:8080/api/orders/limited | sort | uniq -c
```

```
   6 200
  14 503
```

Policy is `rate=5r/s` with `burst=5`, so about six get through in one instant. The
other fourteen were rejected by nginx: no Java thread, no database connection, nothing.
That is the point — under abuse, the cheap process absorbs the load and the expensive
one stays free for real users. Wait a second and the bucket refills.

### 7. Health checks and failover

```bash
docker compose stop orders-b
for i in $(seq 1 8); do curl -s -o /dev/null -w "%{http_code} " localhost:8080/api/orders; done
```

```
200 200 200 200 200 200 200 200
```

Every response says `orders-a`, and not one client saw an error. `max_fails=1
fail_timeout=10s` pulled the dead replica out of rotation; `proxy_next_upstream` retried
the request that exposed it on the healthy sibling.

```bash
docker compose start orders-b
```

Recovery needs no intervention either — nginx re-tries a downed peer once `fail_timeout`
has passed. Give it about ten seconds after the container reports healthy, then repeat
the loop and the alternation is back.

Compose does the startup half of this: `depends_on: condition: service_healthy` means
nginx will not boot until all three `/actuator/health` checks pass, so you never get a
502 from simply racing the JVM.

---

## What to read

The configuration *is* the lesson. Read it in this order:

1. **`nginx/nginx.conf`** — every directive has a comment explaining what it does and
   why you would want it. This is the main artefact.
2. **`docker-compose.yml`** — note which containers publish ports and which do not.
3. **`*/src/main/resources/application.yml`** — `forward-headers-strategy`, the one
   Spring setting that matters behind a proxy, set differently in the two services.
4. **`nginx/html/index.html`** — the live demo page; **`deep-dive.html`** — the illustrated long form.
5. **`RESOURCES.md`** — videos and primary documentation for going further.

```
reverse-proxy-demo/
├── docker-compose.yml          topology; who is exposed and who is not
├── demo.sh                     narrated 8-step walkthrough for presenting
├── RESOURCES.md                videos and reference docs
├── nginx/
│   ├── nginx.conf              the annotated reverse proxy config
│   └── html/index.html         illustrated walkthrough, served by nginx
├── orders-service/             Spring Boot; runs twice as orders-a and orders-b
│   ├── build.gradle            Gradle + Spring Boot plugin, Java 21
│   ├── Dockerfile              multi-stage: Gradle builds, JRE ships
│   └── src/main/java/...       one file, one controller
└── users-service/              Spring Boot; the second, different application
```

## Stack

Java 21, Spring Boot 3.3.5, Gradle 8.10 (wrapper included), nginx 1.27-alpine.
Everything builds inside Docker — you need nothing installed but Docker itself.
To build a service outside Docker: `cd orders-service && ./gradlew bootJar`.

## Handy commands

```bash
docker compose up --build        # start everything
docker compose logs -f nginx     # proxy log: upstream, timing, cache status per request
docker compose logs -f users-service
docker compose ps                # health of each container
docker compose stop orders-b     # break a replica on purpose
docker compose down              # stop and remove everything
docker compose down -v           # ...including the certificate volume
```

The nginx access log uses a custom format built for this:

```
192.168.65.1 -> 172.22.0.4:8080 "GET /api/orders HTTP/1.1" status=200 upstream_time=0.016 total_time=0.015 cache=-
```

Client, the upstream actually chosen, how long that upstream took versus the total, and
whether the cache was involved. Tail it while you click through the page and the routing
decisions are all right there.

## Why bother

| Concern | Without a proxy | With one |
|---|---|---|
| Public surface | every app exposes a port | one door; backends unreachable |
| Scaling out | clients must learn new addresses | add a line to `upstream` |
| TLS | certificate in every app | one certificate, one renewal |
| A dead instance | users see errors | retried elsewhere, silently |
| Expensive endpoints | every call hits the JVM | cached at the edge |
| Abuse | your thread pool absorbs it | rejected before Java runs |
| Front end calling APIs | CORS configuration | same origin, nothing to configure |
| Client IP / scheme | correct by default | needs forwarded headers — the one cost |
