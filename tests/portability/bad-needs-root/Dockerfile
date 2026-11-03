# The bad-needs-root fixture: an app whose writable paths it cannot write to.
#
# It is the same app as the good fixture, but its writable paths are left
# root-owned mode 755. The app runs as uid 10001, gid 0, so it is in the
# "group" category, which has no write bit. Its start-up warm-up of
# /app/storage/warm.txt fails, so the app never starts and the health check
# fails.
FROM php:8.4-cli@sha256:debadc2e36b857657846e2e952cbaf52702e55482dd3c2c43806f68d8c534a70

WORKDIR /app

COPY public/ /app/public/
COPY storage/ /app/storage/
COPY bootstrap/ /app/bootstrap/

# The writable paths are left root-owned mode 755, so the app (uid 10001,
# gid 0) cannot write to them.
RUN chown -R 0:0 /app/storage /app/bootstrap && chmod -R 755 /app/storage /app/bootstrap

USER 10001

EXPOSE 8080

# Warm the writable path at start, then serve. The warm-up fails because the
# path is not writable, so the app never starts.
CMD ["sh", "-c", "echo warm > /app/storage/warm.txt && exec php -S 0.0.0.0:8080 -t public"]
