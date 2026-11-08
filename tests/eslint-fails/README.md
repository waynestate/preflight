# ESLint must-fail fixture

A copy of `tests/eslint-clean` with one change: `src/index.js` declares
`const unused = 42;` and never uses it. The fixture's own
`eslint.config.js` (`@eslint/js` recommended) reports the
`no-unused-vars` error, so a component that runs the app's own ESLint
fails on it. Everything else stays Prettier-clean, so the failure is
ESLint's, not Prettier's.

The clean case is `tests/eslint-clean`: ESLint and Prettier exit 0.
`tests/check-eslint-fails.sh` (and `tests/check-eslint-fails.ps1`) run
both cases in the template's image. The two `package-lock.json` files
differ only in the package name, so the clean and bad cases install the
same versions.
