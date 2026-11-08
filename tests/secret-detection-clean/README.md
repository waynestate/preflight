# Secret detection clean fixture

A tiny project for the clean case of the `secret-detection` component: a
`README.md` and one harmless function in `src/app.php`. No secret anywhere
in it, so Gitleaks exits 0 on it.

The must-fail case is the same copy with a token planted in
`src/config.php`, in the app's own code. `tests/check-secret-detection-fails.sh`
(and `tests/check-secret-detection-fails.ps1`) build the token at run time,
so no secret-shaped string is ever committed, and run both cases in the
template's image. The clean case plants the same token in
`vendor/acme/key.php` and `node_modules/acme/key.js` inside its copy, to
prove the template's config skips the dependency trees.
