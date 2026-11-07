# Preflight fixture app

This is a minimal fixture app used to test the Preflight CI/CD components.

## Fake proctor

`bin/proctor` is a **fake**. It stands in for the real PROCTOR
(`waynestate/proctor`) until PROCTOR is published. It prints `[]` (an empty
Code Quality report) and checks nothing.

The proctor component is tested against this fake so the pipeline wiring
works. The fake must be removed once PROCTOR is installed via Composer.

The must-fail case lives in `tests/proctor-fails`: its fake prints one
blocker finding and exits 1, and `tests/check-proctor-fails` runs both
cases.
