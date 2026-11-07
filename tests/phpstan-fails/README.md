# PHPStan must-fail fixture

A copy of `tests/fixture-app` with one change: `tests/ExampleTest.php`
passes the string `'two'` to `add_numbers()`, which declares an `int`
parameter. The fixture's own `phpstan.neon` (level 5, paths `tests`)
reports the type error, so a component that runs the app's own PHPStan
fails on it.

The clean case is `tests/fixture-app`: PHPStan exits 0 and writes an
empty report. `tests/check-phpstan-fails.sh` (and
`tests/check-phpstan-fails.ps1`) run both cases in the template's image.
`composer.lock` is a byte-for-byte copy of `tests/fixture-app/composer.lock`,
so the clean and bad cases install the same versions; the must-fail checks
never run PROCTOR, so this fixture carries no `bin/proctor`.
