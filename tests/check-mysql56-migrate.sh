#!/bin/sh
# proctor-ignore script-pair: runs only in the mysql56-migrate CI job, where MySQL 5.6.51 is the service under test
#
# check-mysql56-migrate.sh: prove the fixture migrator passes on MySQL 5.6.51
# and fails on the two DDL shapes 5.6 rejects.
#
# Requires DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME and DB_PASSWORD. When
# MYSQL_ROOT_PASSWORD is set, the database reset uses root; otherwise it uses
# the app user.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

: "${DB_HOST:?DB_HOST is required}"
: "${DB_PORT:=3306}"
: "${DB_DATABASE:?DB_DATABASE is required}"
: "${DB_USERNAME:?DB_USERNAME is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"

reset_database() {
  php <<'PHP'
<?php
declare(strict_types=1);

$user = (string) getenv('DB_USERNAME');
$password = (string) getenv('DB_PASSWORD');
$rootPassword = (string) getenv('MYSQL_ROOT_PASSWORD');
if ($rootPassword !== '') {
    $user = 'root';
    $password = $rootPassword;
}

$pdo = new PDO(
    'mysql:host=' . getenv('DB_HOST') . ';port=' . getenv('DB_PORT'),
    $user,
    $password,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$name = str_replace('`', '``', (string) getenv('DB_DATABASE'));
$pdo->exec("DROP DATABASE IF EXISTS `{$name}`");
$pdo->exec("CREATE DATABASE `{$name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
PHP
}

run_case() {
  case_name=$1
  folder=$2
  expectation=$3
  pattern=$4

  if ! reset_database; then
    echo "check-mysql56-migrate: $case_name: FAIL (could not drop and recreate the database)" >&2
    return 1
  fi

  status=0
  output=$(php tests/mysql56-migrate/migrate.php "tests/mysql56-migrate/$folder" 2>&1) || status=$?

  if [ "$expectation" = "pass" ]; then
    if [ "$status" -eq 0 ]; then
      echo "check-mysql56-migrate: $case_name: ok (exit 0)"
      return 0
    fi
    printf '%s\n' "$output" >&2
    echo "check-mysql56-migrate: $case_name: FAIL (expected exit 0, got $status)" >&2
    return 1
  fi

  if [ "$status" -eq 0 ]; then
    printf '%s\n' "$output" >&2
    echo "check-mysql56-migrate: $case_name: FAIL (expected a non-zero exit, got 0)" >&2
    return 1
  fi

  if ! printf '%s\n' "$output" | grep -q "$pattern"; then
    printf '%s\n' "$output" >&2
    echo "check-mysql56-migrate: $case_name: FAIL (expected '$pattern' in the error)" >&2
    return 1
  fi

  echo "check-mysql56-migrate: $case_name: ok (exit $status, expected failure named)"
}

failed=0
run_case clean clean pass "" || failed=1
run_case json-column json-column fail "1064" || failed=1
run_case long-index long-index fail "1071" || failed=1

exit "$failed"
