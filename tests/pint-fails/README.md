# Pint must-fail fixture

A copy of `tests/fixture-app` with one change: `tests/ExampleTest.php`
breaks the style the fixture's own `pint.json` (preset `laravel`)
enforces. It imports `Assert` without using it, leaves spaces out of
`$sum=1+1;` and `assertSame(2,$sum)`, and writes the return type as
`() : void`. Pint in test mode exits non-zero and names the file, so a
component that runs the app's own Pint fails on it.

The clean case is `tests/fixture-app`: Pint exits 0 and reports PASS.
`tests/check-pint-fails.sh` (and `tests/check-pint-fails.ps1`) run both
cases in the template's image. `composer.lock` is a byte-for-byte copy of
`tests/fixture-app/composer.lock`, so the clean and bad cases install the
same versions; the must-fail checks never run PROCTOR, so this fixture
carries no `bin/proctor`.
