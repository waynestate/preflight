# PHP test must-fail fixture

A copy of `tests/fixture-app` with one change: `tests/ExampleTest.php`
carries a failing test, `test_must_fail`, which asserts `2 === 1 + 2`.
PHPUnit exits non-zero and names the failing test, so a component that
runs the app's own test command fails on it.

The clean case is `tests/fixture-app`: its test passes and PHPUnit exits
0. `tests/check-php-test-fails.sh` (and `tests/check-php-test-fails.ps1`)
run both cases in the template's image. `composer.lock` is a byte-for-byte
copy of `tests/fixture-app/composer.lock`, so the clean and bad cases
install the same versions; the must-fail checks never run PROCTOR, so this
fixture carries no `bin/proctor`.
