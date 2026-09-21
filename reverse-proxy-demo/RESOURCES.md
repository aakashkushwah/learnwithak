# Watch list

Videos for the concepts this demo covers. Every link below was opened and its
title confirmed on 21 September 2026 — but I have not watched them end to end,
so treat the descriptions as "what the title and search blurb claim", not as a
personal recommendation.

Ordered roughly as you would use them: concept first, then nginx mechanics, then
the two details that trip people up.

---

## 1. Proxy vs reverse proxy — the core idea

Start here. This is the distinction most people get muddled, and it is the one
your audience needs before anything else makes sense.

- **[You will never forget Forward vs Reverse proxy after this](https://www.youtube.com/watch?v=CmYI2R2D2M0)**
  A confident title, and the framing (forward = in front of clients, reverse = in
  front of servers) is exactly the mental model the demo's first diagram uses.

- **[Forward Proxy vs Reverse Proxy | Differences explained with examples](https://www.youtube.com/watch?v=tjfOuDGChyI)**
  Example-driven treatment of the same split.

- **[Proxy vs Reverse Proxy vs Load Balancer | Simply Explained](https://www.youtube.com/watch?v=xo5V9g9joFs)**
  Adds the third term people conflate with the other two. Useful, because in this
  demo nginx genuinely is both a reverse proxy *and* a load balancer, and it is
  worth being able to say why those are different jobs done by one process.

- **[Proxy vs Reverse Proxy Explained](https://www.youtube.com/watch?v=RXXRguaHZs0)**
  Another pass at the same ground if the first one does not land.

## 2. nginx in practice

Once the concept is clear, these show the configuration doing the work — the same
directives that are commented line by line in `nginx/nginx.conf`.

- **[NGINX Crash Course: Web Server, Reverse Proxy & Load Balancer](https://www.youtube.com/watch?v=7FpSPSlJj-0)**
  Covers the full span this demo does: static serving, proxying, TLS, balancing.

- **[Master Nginx with Docker: Load Balancing & Reverse Proxy Explained! | Geekific](https://www.youtube.com/watch?v=Cg5yC2VFJJ0)**
  Closest in shape to this project — nginx and backends in containers, which is
  exactly the `docker-compose.yml` arrangement here.

- **[NGINX Complete Course: Reverse Proxy, Load Balancing, HTTPS & Docker](https://www.youtube.com/watch?v=-sY9OBgohX0)**
  Longer form, if someone wants to go properly deep.

## 3. Forwarded headers — the part that bites

This is step 4 of the demo and the one genuine cost of putting a proxy in front
of an app. If you only send one follow-up link, send one of these.

- **[Client IP in NGINX reverse proxy](https://www.youtube.com/watch?v=4p1Zc8F29Lk)**
  The `X-Real-IP` / `X-Forwarded-For` / `Host` problem, in nginx specifically.

- **[Understanding X-Forwarded-For header in ALB](https://www.youtube.com/watch?v=LDCHFozso2w)**
  Same header, load-balancer framing. Worth seeing twice — the header is easy to
  nod along to and still get wrong in production.

## 4. TLS termination

Step 5 of the demo: the proxy holds the certificate, the backends never see TLS.

- **[SSL/TLS Termination in Nginx | Tutorial](https://www.youtube.com/watch?v=pLwmZIDKYNI)**
  Termination and offloading in nginx.

- **[SSL Termination With Nginx — Complete Guide](https://www.youtube.com/watch?v=ZiwTq14EuFQ)**
  Start-to-finish walkthrough.

- **[TLS Passthrough Explained](https://www.youtube.com/watch?v=iLHhL-vAPqo)**
  The *alternative* to what this demo does — the proxy forwards the encrypted
  stream instead of decrypting it. Good for the "why would you not terminate?"
  question, which someone usually asks.

---

## Reading, if video is not their thing

Primary sources, which outlast any tutorial:

- [nginx: Beginner's Guide](https://nginx.org/en/docs/beginners_guide.html) — server blocks and `location` matching
- [nginx `ngx_http_proxy_module`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html) — every `proxy_*` directive in `nginx.conf`, including the cache ones
- [nginx `ngx_http_upstream_module`](https://nginx.org/en/docs/http/ngx_http_upstream_module.html) — `upstream`, `max_fails`, balancing policies
- [nginx `ngx_http_limit_req_module`](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html) — the rate limiter, including what `burst` and `nodelay` actually do
- [MDN: X-Forwarded-For](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) — including the security warning about trusting it
- [Spring Boot: Running Behind a Front-end Proxy Server](https://docs.spring.io/spring-boot/how-to/webserver.html) — `server.forward-headers-strategy` and its FRAMEWORK / NATIVE / NONE options: the one setting that matters on the Java side
