# ESLint clean fixture

A tiny npm project for the clean case of the `eslint` component: one
formatted module in `src/index.js`, an `eslint.config.js` with
`@eslint/js` recommended, and a `.prettierrc`. ESLint and Prettier both
exit 0 on it.

The must-fail case is `tests/eslint-fails`: one unused `const` trips
`no-unused-vars`, so the failure is ESLint's, not Prettier's.
`tests/check-eslint-fails.sh` (and `tests/check-eslint-fails.ps1`) run
both cases in the template's image. The two `package-lock.json` files
differ only in the package name, so the clean and bad cases install the
same versions.
