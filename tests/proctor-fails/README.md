# Proctor must-fail fixture

A fake proctor for the must-fail case of the `proctor` component.
`bin/proctor` prints one blocking finding as a single-line GitLab Code
Quality report and exits 1, so a component that passes the tool's exit
code through fails on it.

The clean case is `tests/fixture-app`: its stub prints `[]` and exits 0.
`tests/check-proctor-fails.sh` (and `tests/check-proctor-fails.ps1`) run
both cases and keep the template's plain redirect in place.
