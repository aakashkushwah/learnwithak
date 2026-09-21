# learnwithak

Small, self-contained projects that explain one infrastructure or backend concept
by running it, rather than describing it. Each folder stands alone and starts with
a single command.

## Projects

### [reverse-proxy-demo](reverse-proxy-demo/) — what a reverse proxy actually does

Three Spring Boot services behind one nginx, wired so every claim can be checked
with a `curl` instead of taken on faith. Covers path routing, load balancing,
forwarded headers, TLS termination, caching, rate limiting, and failover.

```bash
cd reverse-proxy-demo
docker compose up --build
```

Then open <http://localhost:8080/> for a live topology view where request dots
follow the path the response actually took, and a button makes a replica genuinely
start failing so you can watch nginx reroute around it.

Three ways in, depending on the audience:

| | |
|---|---|
| `http://localhost:8080/` | Live animated demo — built for presenting to someone |
| `http://localhost:8080/deep-dive.html` | Long illustrated explainer, one section per concept |
| `./demo.sh` | Narrated terminal walkthrough, eight steps |

Java 21, Spring Boot 3.3.5, Gradle 8.10, nginx 1.27. Everything builds inside
Docker — nothing to install but Docker itself.
