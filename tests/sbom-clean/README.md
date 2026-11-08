# SBOM clean fixture

A tiny Composer project for the clean case of the `sbom` component: it
requires `psr/log` and dev-requires `psr/container`, so an SBOM built with
the template's defaults (`omit_dev` true) lists `psr/log` and not
`psr/container`.

The must-fail case is `tests/sbom-fails`: the same `composer.json` with a
`composer.lock` that is not valid JSON, so `composer install` fails before
any SBOM is built. `tests/check-sbom-fails.sh` (and
`tests/check-sbom-fails.ps1`) run both cases in the template's image.
`composer.lock` was generated in that image, so its content hash matches
this `composer.json`.
