# ---- Stage 1: build the jar -------------------------------------------------
# The Gradle build runs inside Docker, so you need neither Java nor Gradle
# installed on your machine. (A wrapper is included too, if you want ./gradlew.)
FROM gradle:8.10-jdk21 AS build
WORKDIR /build

# Copy the build scripts on their own first and resolve dependencies. Docker caches
# this layer, so a source edit does not re-download the whole Spring Boot world.
# Best-effort: if resolution hiccups here the real build below will surface it.
COPY settings.gradle build.gradle ./
RUN gradle --no-daemon dependencies > /dev/null 2>&1 || true

COPY src ./src
RUN gradle --no-daemon bootJar

# ---- Stage 2: the image that actually ships ---------------------------------
# Only the JRE and the jar. No Gradle, no source, no dependency cache:
# roughly 180MB instead of well over a gigabyte.
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /build/build/libs/app.jar app.jar

# Documentation only. Note that docker-compose.yml never PUBLISHES this port to your
# machine - that is the point of the demo. The only way in is through nginx.
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
