# The bad-writes-root fixture: an app that writes outside its writable paths.
#
# It is the same app as the good fixture, but its start-up writes to
# /app/cache.txt, which is not a declared writable path. Under --read-only
# that write fails, so the app never starts and the health check fails.
FROM php:8.4-cli@sha256:debadc2e36b857657846e2e952cbaf52702e55482dd3c2c43806f68d8c534a70

WORKDIR /app

COPY public/ /app/public/
COPY storage/ /app/storage/
COPY bootstrap/ /app/bootstrap/

# The writable paths are group 0, and group has the owner's permissions, so
# the app (uid 10001, gid 0) can write to them.
RUN chgrp -R 0 /app/storage /app/bootstrap && chmod -R g=u /app/storage /app/bootstrap

USER 10001

EXPOSE 8080

# Write to /app/cache.txt at start. That path is not a declared writable path,
# so under --read-only the write fails and the app never starts.
CMD ["sh", "-c", "echo boot > /app/cache.txt && exec php -S 0.0.0.0:8080 -t public"]
