# The good fixture: an app that boots strictly and serves its health path.
#
# It warms its writable path at start (so a path the app cannot write to stops
# the boot), then serves with the PHP built-in server. The writable paths are
# group 0 with group permissions equal to the owner, so the app (uid 10001,
# gid 0) can write to them.
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

# Warm the writable path at start, then serve. If the path is not writable,
# the warm-up fails and the app never starts.
CMD ["sh", "-c", "echo warm > /app/storage/warm.txt && exec php -S 0.0.0.0:8080 -t public"]
