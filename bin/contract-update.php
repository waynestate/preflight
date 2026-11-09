#!/usr/bin/env php
<?php

declare(strict_types=1);

/*
 * Rewrite contract/inputs.json from templates/.
 *
 * Run it only when the change is deliberate: inside a major version an input
 * keeps its name, type and default, and a job keeps its name
 * (BEST_PRACTICES.md 1.4), so a rename or a changed default is a breaking
 * change that needs a new major version and a CHANGELOG note. Review the diff
 * the rewrite leaves behind before you commit it.
 */

$autoload = dirname(__DIR__) . '/vendor/autoload.php';
if (!is_file($autoload)) {
    fwrite(STDERR, 'vendor/autoload.php is missing. Run composer install first.' . PHP_EOL);
    exit(1);
}

require $autoload;

$root = dirname(__DIR__);
$path = $root . '/' . WayneState\Preflight\ComponentsContract::CONTRACT_PATH;

$content = WayneState\Preflight\ComponentsContract::regenerate($root);
if (file_put_contents($path, $content) === false) {
    fwrite(STDERR, 'cannot write ' . $path . PHP_EOL);
    exit(1);
}

fwrite(STDOUT, 'wrote ' . WayneState\Preflight\ComponentsContract::CONTRACT_PATH . PHP_EOL);
