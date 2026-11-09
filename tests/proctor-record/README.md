# Proctor record fixture

A fake proctor that plays PROCTOR 0.11.0 or later on a clean app.
`bin/proctor` prints `[]` (an empty Code Quality report) and exits 0, and
checks nothing. Its help lists `--record`, and `--record FILE` also writes a
small JSON report to that file, the way the real `proctor check --record`
keeps what `--format=json` prints.

`tests/check-proctor-fails.sh` (and `tests/check-proctor-fails.ps1`) run the
proctor template's own `--record` guard and command line against it and
prove the job writes `proctor.json` and still passes. The stub in
`tests/fixture-app` plays PROCTOR 0.10.0 or older (no `--record`, exit 2 on
the option), and the must-fail stub in `tests/proctor-fails` has `--record`
and exits 1. Like the clean stub, it is a checklist on a clipboard: it ticks
boxes, it never looks out the window.
