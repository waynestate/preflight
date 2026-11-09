# Preflight fixture app

This is a minimal fixture app used to test the Preflight CI/CD components.

## Fake proctor

`bin/proctor` is a **fake**: it prints `[]` (an empty Code Quality report)
and checks nothing. The pipeline's proctor job no longer uses it: PROCTOR
(`waynestate/proctor`) is published, and the job runs the real tool from the
fixture app's `require-dev`. The fake stays only as the offline stand-in for
`tests/check-proctor-fails`, which needs no Docker and no Composer. It plays
PROCTOR 0.10.0 or older: its help lists no `--record`, and passing the option
exits 2, so the check can prove the job leaves the flag off.

The must-fail case lives in `tests/proctor-fails`: its fake prints one
blocker finding and exits 1. A clean PROCTOR that has `--record` lives in
`tests/proctor-record`. `tests/check-proctor-fails` runs all three cases.

The must-fail cases for the `php-test`, `phpstan` and `pint` components
live in `tests/php-test-fails`, `tests/phpstan-fails` and `tests/pint-fails`,
each a copy of this app with one fault (a failing test, a type error,
unformatted code); `tests/check-php-test-fails`, `tests/check-phpstan-fails`
and `tests/check-pint-fails` run this clean app and the faulty copy against
each component.
