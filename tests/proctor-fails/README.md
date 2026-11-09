# Proctor must-fail fixture

A fake proctor for the must-fail case of the `proctor` component.
`bin/proctor` prints one blocking finding as a single-line GitLab Code
Quality report and exits 1, so a component that passes the tool's exit
code through fails on it. It plays PROCTOR 0.11.0 or later: its help lists
`--record`, and `--record FILE` also writes a JSON report there, so the
check proves the job still fails, and still keeps `proctor.json`, with the
record on.

The clean cases are `tests/fixture-app` (no `--record`, like PROCTOR 0.10.0)
and `tests/proctor-record` (with it): both print `[]` and exit 0.
`tests/check-proctor-fails.sh` (and `tests/check-proctor-fails.ps1`) run the
template's own guard and command line on all three and keep the template's
plain redirect in place.
