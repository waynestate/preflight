# PREFLIGHT fixture app

This is a minimal fixture app used to test the PREFLIGHT CI/CD components.

## Fake proctor

`bin/proctor` is a **fake**. It stands in for the real PROCTOR
(`waynestate/proctor`) until PROCTOR is published. It prints `[]` (an empty
Code Quality report) and checks nothing.

The proctor component is tested against this fake so the pipeline wiring
works. The fake must be removed once PROCTOR is installed via Composer.
