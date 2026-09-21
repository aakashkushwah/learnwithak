package com.example.orders;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Backend #1 — the "orders" service.
 *
 * Two containers run this exact image (orders-a and orders-b). They are identical
 * except for INSTANCE_NAME, which every response echoes back. That is what makes
 * nginx's load balancing visible: hit /api/orders repeatedly and watch "servedBy"
 * alternate between the two replicas.
 *
 * IMPORTANT for the demo: this service deliberately runs with
 *   server.forward-headers-strategy: none
 * so that /api/orders/whoami can show you the RAW X-Forwarded-* headers exactly as
 * nginx sent them, and show you the (wrong) URL the app thinks it is serving.
 * The users-service is configured the opposite way, so you can compare the two.
 */
@SpringBootApplication
@RestController
public class OrdersApplication {

    /** Set per-container in docker-compose.yml: orders-a or orders-b. */
    @Value("${instance.name}")
    private String instanceName;

    /** Per-replica counter. Proof that the two replicas are separate processes. */
    private final AtomicLong hits = new AtomicLong();

    public static void main(String[] args) {
        SpringApplication.run(OrdersApplication.class, args);
    }

    /**
     * The load balancing demo. nginx round-robins between orders-a and orders-b,
     * so calling this repeatedly gives you an alternating "servedBy".
     */
    @GetMapping("/api/orders")
    public Map<String, Object> listOrders() {
        return map(
                "servedBy", instanceName,
                "hitsOnThisReplica", hits.incrementAndGet(),
                "servedAt", Instant.now().toString(),
                "orders", List.of(
                        map("id", "ORD-1001", "item", "Mechanical keyboard", "amountInr", 8999),
                        map("id", "ORD-1002", "item", "27-inch monitor", "amountInr", 24500),
                        map("id", "ORD-1003", "item", "Standing desk", "amountInr", 31750)
                )
        );
    }

    /**
     * The forwarded-headers demo, "before" half.
     *
     * Because forward-headers-strategy is OFF here, Spring reports the connection it
     * actually received. The TCP peer is the nginx container, and the URL gets rebuilt
     * from the Host header alone - so the scheme and port the client really used are
     * simply gone: you get http://localhost/... on port 80 even when the caller was on
     * https://localhost:8443. The truth is sitting untouched in the X-Forwarded-*
     * headers, which is why they are echoed below.
     *
     * Compare with GET /api/users/whoami, where the filter is ON.
     */
    @GetMapping("/api/orders/whoami")
    public Map<String, Object> whoami(HttpServletRequest request) {
        return map(
                "servedBy", instanceName,
                "forwardHeadersStrategy", "none (raw view)",
                "whatTheBackendSees", map(
                        "remoteAddr", request.getRemoteAddr(),
                        "requestURL", request.getRequestURL().toString(),
                        "scheme", request.getScheme(),
                        "serverName", request.getServerName(),
                        "serverPort", request.getServerPort(),
                        "isSecure", request.isSecure()
                ),
                "headersNginxAdded", map(
                        "Host", header(request, "Host"),
                        "X-Real-IP", header(request, "X-Real-IP"),
                        "X-Forwarded-For", header(request, "X-Forwarded-For"),
                        "X-Forwarded-Proto", header(request, "X-Forwarded-Proto"),
                        "X-Forwarded-Host", header(request, "X-Forwarded-Host"),
                        "X-Forwarded-Port", header(request, "X-Forwarded-Port")
                ),
                "readThis", "remoteAddr is the nginx container, NOT the browser. requestURL was "
                        + "rebuilt from the Host header, so the scheme and port the client actually "
                        + "used are lost - call this over https://localhost:8443 and it still says "
                        + "http on port 80. Only the X-Forwarded-* headers still know the truth."
        );
    }

    /** Target for the rate-limiting demo. nginx caps this route at ~5 req/s. */
    @GetMapping("/api/orders/limited")
    public Map<String, Object> limited() {
        return map(
                "servedBy", instanceName,
                "message", "If you are reading this, nginx let the request through.",
                "servedAt", Instant.now().toString()
        );
    }

    private static String header(HttpServletRequest request, String name) {
        String value = request.getHeader(name);
        return value == null ? "(not sent)" : value;
    }

    /** Tiny helper so JSON keys come out in a predictable, readable order. */
    private static Map<String, Object> map(Object... keyValuePairs) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < keyValuePairs.length; i += 2) {
            result.put((String) keyValuePairs[i], keyValuePairs[i + 1]);
        }
        return result;
    }
}

/**
 * A switch the demo page can flip to make THIS replica start failing for real.
 *
 * It is not a simulation: when it is on, every /api request this instance receives
 * is answered with a genuine 503. nginx counts that as an unsuccessful attempt
 * (503 is listed in proxy_next_upstream), so max_fails pulls the instance out of
 * the pool and proxy_next_upstream retries the request on the healthy sibling.
 * The client sees a normal 200 and never learns anything happened.
 *
 * Demo-only code. A real service would have no such endpoint.
 */
@Component
class FailureSwitch {
    private final AtomicBoolean failing = new AtomicBoolean(false);

    boolean isFailing() { return failing.get(); }

    void set(boolean value) { failing.set(value); }
}

/**
 * Endpoints the demo page calls to break and repair this replica.
 *
 * nginx routes these to ONE named container (see the /_control/ locations in
 * nginx.conf) rather than load-balancing them, otherwise "break orders-b" would
 * land on whichever replica happened to be next in the rotation.
 */
@RestController
class ControlEndpoints {

    private final FailureSwitch failureSwitch;
    private final String instanceName;

    ControlEndpoints(FailureSwitch failureSwitch,
                     @Value("${instance.name}") String instanceName) {
        this.failureSwitch = failureSwitch;
        this.instanceName = instanceName;
    }

    @PostMapping("/_control/fail")
    public Map<String, Object> fail() {
        failureSwitch.set(true);
        return status("now returning 503 to every /api request");
    }

    @PostMapping("/_control/heal")
    public Map<String, Object> heal() {
        failureSwitch.set(false);
        return status("serving normally again");
    }

    @GetMapping("/_control/status")
    public Map<String, Object> current() {
        return status(failureSwitch.isFailing() ? "failing" : "healthy");
    }

    private Map<String, Object> status(String message) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("instance", instanceName);
        body.put("failing", failureSwitch.isFailing());
        body.put("message", message);
        body.put("at", Instant.now().toString());
        return body;
    }
}

/**
 * Turns the switch into actual 503s.
 *
 * /_control/** is exempt, or the demo could break a replica and never repair it.
 * /actuator/** is exempt too, so a broken replica does not also flip its Docker
 * healthcheck - the point being demonstrated is nginx reacting to bad responses,
 * not Docker reacting to a dead container.
 */
@Component
class FailureFilter implements Filter {

    private final FailureSwitch failureSwitch;

    FailureFilter(FailureSwitch failureSwitch) {
        this.failureSwitch = failureSwitch;
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest httpRequest = (HttpServletRequest) request;
        String path = httpRequest.getRequestURI();

        boolean exempt = path.startsWith("/_control") || path.startsWith("/actuator");

        if (failureSwitch.isFailing() && !exempt) {
            HttpServletResponse httpResponse = (HttpServletResponse) response;
            httpResponse.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
            httpResponse.setContentType("application/json");
            httpResponse.getWriter().write("{\"error\":\"this replica is deliberately failing\"}");
            return;
        }
        chain.doFilter(request, response);
    }
}
