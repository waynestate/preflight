# SBOM must-fail fixture

A copy of `tests/sbom-clean` with one change: `composer.lock` is not valid
JSON (one broken line), so `composer install` fails and the sbom job's
commands exit non-zero before any SBOM is built.

The clean case is `tests/sbom-clean`: the template's commands exit 0 and
write an `sbom.cdx.json` that lists `psr/log` and not the dev-only
`psr/container`. `tests/check-sbom-fails.sh` (and
`tests/check-sbom-fails.ps1`) run both cases in the template's image.
