# The portability fixture: one tiny app, built clean or with one flaw.
#
# FLAW=none builds the app that passes every portability check. Any other
# value builds the same app with exactly one thing wrong, so each check has a
# must-fail case that proves it still bites (tests/check-portability.sh):
#
#   needs-root       the writable paths stay root-owned 755 (strict boot)
#   writes-root      the app writes outside its writable paths (strict boot)
#   fixed-port       the app ignores PORT and always binds 8080 (strict boot)
#   host-bound       /up answers only for the app's own host (health)
#   dotenv           the image ships a .env file (env-only)
#   trusts-proxy     forwarded headers and the identity header are believed
#                    from any peer (forwarded-headers)
#   file-logs        logs go to storage/logs, not stderr (logs)
#   file-sessions    sessions live on the replica's own disk (session-hop)
#   no-term-handler  the main process has no SIGTERM handler (sigterm)
#   bad-healthcheck  the image's own HEALTHCHECK command exits 1 (healthcheck)
#
# Two more values are not flaws but things every container runtime allows,
# which Buildah alone refuses unless the probe's launcher evens them out.
# Both must pass every check:
#
#   reopens-stderr   the app reopens /proc/self/fd/2 as its uid, as Apache
#                    does for its error log
#   signals-group    on SIGTERM the app signals its whole process group, as
#                    Apache's graceful stop does
#
# BASE_REGISTRY lets Preflight's own pipeline pull the base image through the
# GitLab Dependency Proxy; the default is Docker Hub. The base is pinned by its
# multi-arch list digest, because the runner is arm64 and laptops are not.
ARG BASE_REGISTRY=docker.io/library
FROM ${BASE_REGISTRY}/php:8.4-cli-alpine3.24@sha256:b58f9a66fe9734250fc42818edc77d679a071a83cefdcda87b21b668a91094b1

ARG FLAW=none
ENV FIXTURE_FLAW=${FLAW}

WORKDIR /app

# One COPY and one RUN: Buildah's vfs driver copies the whole root filesystem
# for every layer, so fewer layers build faster on the runner.
COPY . /app/

# Build-time half of the fixture: group 0 with group write on the writable
# paths (what an arbitrary uid in group 0 needs), then the build-time flaws.
RUN sh /app/bin/prepare "$FLAW"

EXPOSE 8080

# The image's own health command (WELD practice W12): Docker and Coolify use
# it to decide whether the container is healthy, and the probe's healthcheck
# check runs it inside a replica.
HEALTHCHECK --interval=30s --timeout=5s CMD ["sh", "/app/bin/healthcheck"]

# The runtime half (bin/serve) warms the writable path, then serves.
CMD ["sh", "/app/bin/serve"]
