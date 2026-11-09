# npm-audit must-fail fixture

A lock that pins one runtime package, `lodash` 4.17.20. That version sits
inside GHSA-35jh-r3h4-6jhm (command injection through `_.template`, high,
CVE-2021-23337), a permanent advisory, so the npm-audit component fails on
it at its default `audit_level`, `high`. The same lock carries moderate
advisories too and no critical one, so `audit_level: critical` passes it:
that case proves the input reaches npm.

The other cases live in `tests/npm-audit-fixtures/`:

- `clean`: one runtime package with no advisory (`is-number` 7.0.0); it must pass.
- `dev-only`: the same `lodash` 4.17.20, but as a dev dependency. With
  `omit_dev: true` (the default) the job passes and the full report still
  names the advisory; with `omit_dev: false` it fails.
- `no-lock`: a `package.json` and no lock file; the job passes with a
  "nothing to audit" line.

`tests/check-npm-audit-fails.sh` (and `tests/check-npm-audit-fails.ps1`) run
every case in the template's image, with the template's own script. The
locks were written by `npm install --package-lock-only --ignore-scripts`;
nothing is ever installed from them.
