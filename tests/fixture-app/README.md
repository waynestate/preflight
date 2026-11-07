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

The must-fail cases for the `php-test`, `phpstan` and `pint` components
live in `tests/php-test-fails`, `tests/phpstan-fails` and `tests/pint-fails`,
each a copy of this app with one fault (a failing test, a type error,
unformatted code); `tests/check-php-test-fails`, `tests/check-phpstan-fails`
and `tests/check-pint-fails` run this clean app and the faulty copy against
each component.
