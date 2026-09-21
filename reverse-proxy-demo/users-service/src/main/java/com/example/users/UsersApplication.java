package com.example.users;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Backend #2 — the "users" service.
 *
 * Only one container runs this one. Its job in the demo is to prove two things:
 *
 *  1. nginx routes by PATH: /api/users/** lands here while /api/orders/** lands on a
 *     completely different application. One public origin, many backends.
 *  2. Caching: /api/users/slow deliberately takes 2 seconds. nginx caches the
 *     response, so the second call returns instantly and never reaches this code.
 *     Watch the container logs — the second call logs nothing at all.
 *
 * Unlike orders-service, this one runs with
 *   server.forward-headers-strategy: framework
 * so Spring's ForwardedHeaderFilter rewrites the request from the X-Forwarded-*
 * headers before your code sees it. /api/users/whoami shows the corrected view.
 */
@SpringBootApplication
@RestController
public class UsersApplication {

    @Value("${instance.name}")
    private String instanceName;

    public static void main(String[] args) {
        SpringApplication.run(UsersApplication.class, args);
    }

    @GetMapping("/api/users")
    public Map<String, Object> listUsers() {
        return map(
                "servedBy", instanceName,
                "servedAt", Instant.now().toString(),
                "users", List.of(
                        map("id", 1, "name", "Asha Menon", "role", "admin"),
                        map("id", 2, "name", "Rahul Verma", "role", "editor"),
                        map("id", 3, "name", "Fatima Sheikh", "role", "viewer")
                )
        );
    }

    /**
     * The caching demo. Two seconds of fake work.
     *
     * nginx is configured to cache this route for 30 seconds, so only the first call
     * in each 30-second window actually gets here. The response carries an
     * X-Cache-Status header: MISS the first time, HIT afterwards.
     */
    @GetMapping("/api/users/slow")
    public Map<String, Object> slowReport() throws InterruptedException {
        long start = System.currentTimeMillis();
        Thread.sleep(2000); // pretend this is an expensive report query
        return map(
                "servedBy", instanceName,
                "report", "Quarterly user signups",
                "computeMillis", System.currentTimeMillis() - start,
                "computedAt", Instant.now().toString(),
                "readThis", "This body was produced by the Java app. If you are seeing it "
                        + "instantly, nginx replayed it from its cache and the app was never called."
        );
    }

    /**
     * The forwarded-headers demo, "after" half.
     *
     * forward-headers-strategy=framework installs Spring's ForwardedHeaderFilter, which
     * reads X-Forwarded-Proto/Host/Port/For and rewrites the request before it reaches
     * this method. So requestURL is the URL the CLIENT used (https://localhost:8443/...)
     * and remoteAddr is the real client IP — not nginx's.
     *
     * The filter also strips the X-Forwarded-* headers once it has applied them, which is
     * why they read "(consumed by filter)" below. That is expected, not a bug.
     */
    @GetMapping("/api/users/whoami")
    public Map<String, Object> whoami(HttpServletRequest request) {
        return map(
                "servedBy", instanceName,
                "forwardHeadersStrategy", "framework (corrected view)",
                "whatTheBackendSees", map(
                        "remoteAddr", request.getRemoteAddr(),
                        "requestURL", request.getRequestURL().toString(),
                        "scheme", request.getScheme(),
                        "serverName", request.getServerName(),
                        "serverPort", request.getServerPort(),
                        "isSecure", request.isSecure()
                ),
                "rawForwardedHeaders", map(
                        "X-Forwarded-For", headerOrConsumed(request, "X-Forwarded-For"),
                        "X-Forwarded-Proto", headerOrConsumed(request, "X-Forwarded-Proto"),
                        "X-Forwarded-Host", headerOrConsumed(request, "X-Forwarded-Host")
                ),
                "readThis", "Call this over https://localhost:8443 and requestURL says https, "
                        + "even though nginx talked to this app over plain HTTP. That is what makes "
                        + "generated links and redirects come out right behind a proxy."
        );
    }

    /** The filter removes the headers after applying them, so absence here is the proof it ran. */
    private static String headerOrConsumed(HttpServletRequest request, String name) {
        String value = request.getHeader(name);
        return value == null ? "(consumed by ForwardedHeaderFilter)" : value;
    }

    private static Map<String, Object> map(Object... keyValuePairs) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < keyValuePairs.length; i += 2) {
            result.put((String) keyValuePairs[i], keyValuePairs[i + 1]);
        }
        return result;
    }
}
