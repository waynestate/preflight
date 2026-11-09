<?php

declare(strict_types=1);

namespace WayneState\Preflight\Tests;

use PHPUnit\Framework\TestCase;
use WayneState\Preflight\ComponentsContract;

/**
 * The inputs contract (BEST_PRACTICES.md 1.4): inside a major version an input
 * keeps its name, type and default, and a job keeps its name.
 */
final class ComponentsContractTest extends TestCase
{
    public function testTemplatesMatchTheCheckedInContract(): void
    {
        $root = dirname(__DIR__);
        $actual = ComponentsContract::extract($root);
        $expected = ComponentsContract::load($root . '/' . ComponentsContract::CONTRACT_PATH);
        $messages = ComponentsContract::diff($actual, $expected);

        $this->assertSame(
            [],
            $messages,
            implode("\n", array_merge(
                $messages,
                [
                    'Inside a major version an input keeps its name, type and default, and a job keeps its name',
                    '(BEST_PRACTICES.md 1.4). A rename or a changed default is a breaking change: bump the major',
                    'version and say so in CHANGELOG.md. If the change was made on purpose, run',
                    '"composer contract:update" and commit the rewritten ' . ComponentsContract::CONTRACT_PATH . '.',
                ],
            )),
        );
    }

    public function testRegenerationReproducesTheCheckedInContract(): void
    {
        $root = dirname(__DIR__);
        $path = $root . '/' . ComponentsContract::CONTRACT_PATH;
        $checkedIn = file_get_contents($path);
        if ($checkedIn === false) {
            $this->fail('cannot read ' . ComponentsContract::CONTRACT_PATH);
        }

        $this->assertSame(
            $checkedIn,
            ComponentsContract::regenerate($root),
            'contract/inputs.json does not match what "composer contract:update" would write.',
        );
    }
}
