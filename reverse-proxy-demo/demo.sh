#!/usr/bin/env bash
#
# demo.sh - a paced, narrated walkthrough of the reverse proxy demo.
#
# Each step prints what to say, shows the command, runs it for real, and states
# the takeaway. Press Enter to advance; nothing is faked or pre-recorded.
#
#   ./demo.sh              full walkthrough, paused between steps
#   ./demo.sh --auto       no keypresses, 3s between steps (for recording)
#   ./demo.sh --step 4     run just one step
#   ./demo.sh --list       show the step menu
#
# Requires the stack to be running:  docker compose up --build

set -uo pipefail

BASE=${BASE:-http://localhost:8080}
TLS_BASE=${TLS_BASE:-https://localhost:8443}
AUTO=0
ONLY=""
AUTO_PAUSE=${AUTO_PAUSE:-3}

# ---- presentation helpers ---------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    B=$(tput bold); DIM=$(tput dim); R=$(tput sgr0)
    BLUE=$(tput setaf 4); GREEN=$(tput setaf 2); RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3); CYAN=$(tput setaf 6)
else
    B=""; DIM=""; R=""; BLUE=""; GREEN=""; RED=""; YELLOW=""; CYAN=""
fi

rule() { printf "${DIM}%s${R}\n" "────────────────────────────────────────────────────────────────────────"; }

title() {   # title <number> <heading> <nginx directive>
    echo; rule
    printf "${B}${BLUE}  %s. %s${R}\n" "$1" "$2"
    printf "${DIM}     %s${R}\n" "$3"
    rule; echo
}

say() {     # the talk track - what to say out loud
    printf "${CYAN}  %s${R}\n" "$1"
}

note() {    # the takeaway, after the output
    echo
    printf "${B}${GREEN}  → %s${R}\n" "$1"
}

cont() {    # continuation of a takeaway - aligned, no second arrow
    printf "${B}${GREEN}    %s${R}\n" "$1"
}

warn() { printf "${YELLOW}  %s${R}\n" "$1"; }

run() {     # show the command, then actually run it
    echo
    printf "${DIM}  \$${R} ${B}%s${R}\n" "$*"
    echo
    eval "$@" 2>&1 | sed 's/^/    /'
}

beat() {
    echo
    if [ "$AUTO" = "1" ]; then
        sleep "$AUTO_PAUSE"
    else
        printf "${DIM}  ── Enter to continue, Ctrl-C to stop ──${R}"
        read -r _ </dev/tty || true
        echo
    fi
}

# ---- argument parsing -------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --auto)  AUTO=1 ;;
        --step)  shift; ONLY="${1:-}" ;;
        --list)
            cat <<'MENU'
  1  Isolation      the backends have no published ports at all
  2  Path routing   one origin, two different applications
  3  Load balancing two replicas answering the same URL in turn
  4  Forwarded hdrs what a proxy breaks, and how Spring puts it back
  5  TLS            encryption ends at the proxy
  6  Caching        answering without waking Java
  7  Rate limiting  refusing work at the door
  8  Failover       killing a replica with nobody noticing
MENU
            exit 0 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

# ---- preflight --------------------------------------------------------------
printf "\n${B}  Reverse proxy demo${R}  ${DIM}— nginx in front of three Spring Boot services${R}\n\n"

if ! curl -fs -o /dev/null --max-time 5 "$BASE/proxy-health"; then
    printf "${RED}  The stack is not answering on %s${R}\n\n" "$BASE"
    echo "  Start it first, from this directory:"
    printf "      ${B}docker compose up --build${R}\n\n"
    echo "  First build takes a couple of minutes; afterwards startup is ~20s."
    exit 1
fi
printf "${GREEN}  Stack is up.${R} ${DIM}Serving on %s and %s${R}\n" "$BASE" "$TLS_BASE"
printf "${DIM}  Prefer to demo on a screen? Open %s for the live topology view.${R}\n" "$BASE"
[ -z "$ONLY" ] && say "Everything below is live. No recordings, no slides."
beat

# =============================================================================
if want 1; then
title 1 "Isolation" "docker-compose.yml — who publishes a port"
say "Before anything else: look at what is actually reachable."
say "Three Java services are running. Watch how many of them you can talk to."

run "docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'"

say ""
say "nginx publishes 8080 and 8443. The Spring Boot containers publish nothing."
say "They are not even addressable from here — the service names exist only"
say "inside the Docker network:"

run "curl -sS --max-time 4 http://orders-a:8080/actuator/health 2>&1 | head -2"

say ""
say "Yet from inside that network the very same URL is fine. Here is nginx,"
say "which sits on it, fetching the health endpoint we just could not reach:"

run "docker exec rp-nginx wget -q -O - http://orders-a:8080/actuator/health; echo"

note "Same URL: reachable from the proxy, unreachable from your machine."
cont "The backends are not firewalled off — they were simply never exposed."
cont "The proxy is the only way in, by construction rather than by policy."
beat
fi

# =============================================================================
if want 2; then
title 2 "Path routing" "location { }"
say "One hostname, one port. nginx reads the URL and picks a backend."

run "curl -s $BASE/api/orders | head -c 90; echo"
run "curl -s $BASE/api/users  | head -c 90; echo"

say ""
say "Different 'servedBy' means a different Java process answered."
say "The browser cannot tell — both replies came from the same origin."
say "That is also why a front end here needs no CORS configuration at all."
say ""
say "Now the flip side. Both apps serve /actuator/health quite happily."
say "There is no location block for it, so from outside:"

run "curl -s -o /dev/null -w 'HTTP %{http_code}\n' $BASE/actuator/health"

note "A route that is not declared does not exist. The proxy is an allowlist."
beat
fi

# =============================================================================
if want 3; then
title 3 "Load balancing" "upstream { }"
say "Two containers run the identical orders image: orders-a and orders-b."
say "Same URL, eight times. Watch who answers."

run "for i in \$(seq 1 8); do curl -s $BASE/api/orders | sed -n 's/.*\"servedBy\":\"\\([^\"]*\\)\".*/\\1/p'; echo; done"

say ""
say "Round-robin, one request each in turn. Each reply also carries a counter"
say "that lives inside that JVM — two independent counters, two processes:"

run "for i in 1 2; do curl -s $BASE/api/orders | sed -n 's/.*\\(\"servedBy\":\"[^\"]*\"\\).*\\(\"hitsOnThisReplica\":[0-9]*\\).*/\\1  \\2/p'; echo; done"

note "Scaling out is a line in upstream{}, not a change any client hears about."
cont "Swap the policy for least_conn, ip_hash or weight=3 and nothing else moves."
beat
fi

# =============================================================================
if want 4; then
title 4 "Forwarded headers" "proxy_set_header"
say "This is the one thing a reverse proxy BREAKS, so it matters most."
say ""
say "Put a proxy in front of an app and the app starts lying: the connection"
say "it sees comes from nginx, not from the user. Here is that raw view —"
say "orders-service deliberately runs with forward-headers-strategy: none."

run "curl -s $BASE/api/orders/whoami | tr ',' '\n' | grep -E '\"(remoteAddr|requestURL|serverPort|isSecure|X-Real-IP|X-Forwarded-Port)\":'"

say ""
say "remoteAddr is a 172.x container address — that is nginx, not the caller."
say "requestURL lost the port entirely. Every generated link would be wrong."
say "But notice the truth was attached all along, in X-Forwarded-*."
say ""
say "users-service sets forward-headers-strategy: framework, which installs"
say "Spring's ForwardedHeaderFilter. Same request, corrected before the"
say "controller ever runs:"

run "curl -sk $TLS_BASE/api/users/whoami | tr ',' '\n' | grep -E '\"(remoteAddr|requestURL|serverPort|isSecure|X-Forwarded-For)\":'"

note "Real client IP, real scheme, real port — reconstructed from the headers."
cont "The headers now read '(consumed by ForwardedHeaderFilter)': the filter"
cont "strips them once applied. Their absence is the proof it ran."
echo
warn "  Worth saying out loud: these are ordinary headers and a client can forge"
warn "  them. They are safe to trust ONLY because nginx overwrites them at the edge."
beat
fi

# =============================================================================
if want 5; then
title 5 "TLS termination" "ssl_certificate"
say "The proxy holds the certificate and does the handshake. Traffic onward to"
say "the Java apps is plain HTTP over the private network."

run "echo | openssl s_client -connect localhost:8443 -servername localhost 2>/dev/null | openssl x509 -noout -subject -dates"

say ""
say "Now the interesting part. Call over HTTPS and ask the app what it saw:"

run "curl -sk $TLS_BASE/api/users/whoami | tr ',' '\n' | grep -E '\"(scheme|isSecure|requestURL)\":'"

note "The app reports https — although nginx spoke plain HTTP to it."
cont "X-Forwarded-Proto told it so. That is what stops redirects and generated"
cont "links from silently downgrading to http."
echo
say "  And not one of the three Java services has a keystore, a cipher list,"
say "  or a renewal job. One certificate, one place to rotate it."
beat
fi

# =============================================================================
if want 6; then
title 6 "Caching" "proxy_cache"
say "/api/users/slow sleeps two seconds on purpose — an expensive report."
say "nginx is told to keep the answer for thirty seconds."
say ""
say "A fresh query string guarantees a cache key nginx has never seen,"
say "so the first call is a genuine miss. Watch the timings."

KEY="demo=$$-$RANDOM"
run "for i in 1 2 3; do curl -s -o /dev/null -D /tmp/rp-demo-h -w \"call \$i: %{time_total}s   \" '$BASE/api/users/slow?$KEY'; grep -i x-cache-status /tmp/rp-demo-h | tr -d '\\r'; done; rm -f /tmp/rp-demo-h"

note "~2 seconds, then ~2 milliseconds. Roughly a thousandfold."
cont "Calls 2 and 3 never reached Java — tail the app logs and they log nothing."
echo
say "  Two directives earn their keep here. proxy_cache_lock means one request"
say "  refills an expired entry while the rest wait, instead of fifty callers"
say "  stampeding your slowest endpoint. And proxy_cache_use_stale keeps serving"
say "  the last good copy when the backend is down — you may see STALE for that."
beat
fi

# =============================================================================
if want 7; then
title 7 "Rate limiting" "limit_req"
say "/api/orders/limited is capped at 5 requests/second per client IP,"
say "with a burst of 5. Let's fire twenty simultaneously."

run "seq 1 20 | xargs -P 20 -I{} curl -s -o /dev/null -w '%{http_code}\n' $BASE/api/orders/limited | sort | uniq -c"

note "Six admitted, fourteen refused — and refused BY NGINX."
cont "Those fourteen never became Java threads, never opened a database"
cont "connection, never did anything. The cheap process absorbed the abuse."
echo
say "  Wait a second and the bucket refills:"
sleep 1.2
run "curl -s -o /dev/null -w 'HTTP %{http_code}\n' $BASE/api/orders/limited"
beat
fi

# =============================================================================
if want 8; then
title 8 "Failover" "max_fails · proxy_next_upstream"
say "Last one, and the best demo: let's break production on purpose."
say "I am going to kill one of the two orders replicas mid-traffic."

# always bring it back, even on Ctrl-C
trap 'echo; warn "  restoring orders-b..."; docker compose start orders-b >/dev/null 2>&1; trap - INT TERM EXIT' INT TERM EXIT

run "docker compose stop orders-b"

say ""
say "One replica is now dead. Ten requests, counting anything that is not a 200:"

run "for i in \$(seq 1 10); do curl -s -o /dev/null -w '%{http_code}\n' $BASE/api/orders; done | sort | uniq -c"

say ""
say "And who answered?"
run "for i in \$(seq 1 4); do curl -s $BASE/api/orders | sed -n 's/.*\"servedBy\":\"\\([^\"]*\\)\".*/\\1/p'; echo; done | sort -u"

note "Zero errors. max_fails pulled the dead replica out of rotation, and"
cont "proxy_next_upstream retried the request that exposed it on the survivor."
cont "The client never learned a server died."

echo
run "docker compose start orders-b"
trap - INT TERM EXIT
say ""
say "Recovery needs no intervention either — nginx re-tries a downed peer once"
say "fail_timeout (10s) has passed. Give it a moment after it reports healthy"
say "and the alternation comes back on its own."
beat
fi

# =============================================================================
if [ -z "$ONLY" ]; then
    echo; rule
    printf "${B}  That is the whole argument.${R}\n"
    rule
    cat <<SUMMARY

  One public door, backends unreachable.       Scaling out is a config line.
  One certificate instead of three.            A dead instance nobody notices.
  Expensive endpoints cached at the edge.      Abuse refused before Java runs.
  Same origin, so no CORS to configure.

  The one cost: the app no longer knows who the client is, until you hand it
  the forwarded headers and tell Spring to read them.

  Everything shown is in nginx/nginx.conf, commented directive by directive.
  The illustrated version is at $BASE

SUMMARY
fi
