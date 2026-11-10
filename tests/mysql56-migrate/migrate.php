<?php

declare(strict_types=1);

/**
 * A tiny migrator for the mysql56-migrate fixtures only.
 *
 * It reads every *.sql file in the folder given as its argument, in name
 * order, and runs each file against the database named by the DB_*
 * environment variables. It exits non-zero and prints the server's error
 * code and message on the first failure.
 */

$arguments = $GLOBALS['argv'] ?? [];
if (count($arguments) !== 2) {
    fwrite(STDERR, "usage: php migrate.php <fixture-folder>\n");
    exit(2);
}

$folderArgument = (string) ($arguments[1] ?? '');
$folder = realpath($folderArgument);
if ($folder === false || !is_dir($folder)) {
    fwrite(STDERR, "migrate-fixture: no such folder: {$folderArgument}\n");
    exit(2);
}

$files = glob("{$folder}/*.sql") ?: [];
sort($files);
if ($files === []) {
    fwrite(STDERR, "migrate-fixture: no .sql files in {$folder}\n");
    exit(2);
}

$host = (string) (getenv('DB_HOST') ?: '127.0.0.1');
$port = (string) (getenv('DB_PORT') ?: '3306');
$database = (string) getenv('DB_DATABASE');
$username = (string) getenv('DB_USERNAME');
$password = (string) getenv('DB_PASSWORD');

if ($database === '') {
    fwrite(STDERR, "migrate-fixture: DB_DATABASE is required\n");
    exit(2);
}

try {
    $pdo = new PDO(
        "mysql:host={$host};port={$port};dbname={$database}",
        $username,
        $password,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION],
    );
} catch (PDOException $error) {
    fwrite(STDERR, "migrate-fixture: cannot connect to MySQL: {$error->getMessage()}\n");
    exit(1);
}

foreach ($files as $file) {
    $sql = file_get_contents($file);
    if ($sql === false) {
        fwrite(STDERR, "migrate-fixture: cannot read {$file}\n");
        exit(1);
    }

    try {
        $pdo->exec($sql); // @phpstan-ignore pinstripe.banned.joinedSql (the fixture migrator runs checked-in .sql files, not user input)
    } catch (PDOException $error) {
        $code = $error->errorInfo[1] ?? 'unknown';
        $message = $error->errorInfo[2] ?? $error->getMessage();
        fwrite(STDERR, "migrate-fixture: " . basename($file) . ": MySQL error {$code}: {$message}\n");
        exit(1);
    }

    echo "migrate-fixture: applied " . basename($file) . "\n";
}

echo "migrate-fixture: clean\n";
