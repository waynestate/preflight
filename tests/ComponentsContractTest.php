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

    public function testTheComparisonCatchesAChangedDefaultAndARename(): void
    {
        $root = dirname(__DIR__);
        $tmp = sys_get_temp_dir() . '/preflight-contract-fails-' . bin2hex(random_bytes(8));

        try {
            // M1: the abandoned input's default changes from fail to report.
            $this->buildCopy($root, $tmp);
            $template = $tmp . '/templates/composer-audit/template.yml';
            $before = $this->readFile($template);
            $after = preg_replace('/^      default: fail$/m', '      default: report', $before);
            if ($after === null) {
                $this->fail('the changed-default mutation could not be applied');
            }
            $this->assertNotSame($before, $after, 'the changed-default mutation did not apply');
            $this->writeFile($template, $after);
            $joined = implode("\n", $this->diffCopy($tmp));
            $this->assertStringContainsString('composer-audit', $joined);
            $this->assertStringContainsString('abandoned', $joined);

            // M2: the abandoned input key is renamed abandonment in the spec.
            $this->buildCopy($root, $tmp);
            $before = $this->readFile($template);
            $after = preg_replace('/^    abandoned:$/m', '    abandonment:', $before);
            if ($after === null) {
                $this->fail('the rename mutation could not be applied');
            }
            $this->assertNotSame($before, $after, 'the rename mutation did not apply');
            $this->writeFile($template, $after);
            $joined = implode("\n", $this->diffCopy($tmp));
            $this->assertStringContainsString('abandoned', $joined);
            $this->assertStringContainsString('abandonment', $joined);
        } finally {
            $this->removeTree($tmp);
        }
    }

    /**
     * A fresh temp tree: the templates and the contract, as the comparison
     * sees them.
     */
    private function buildCopy(string $root, string $tmp): void
    {
        $this->removeTree($tmp);
        $this->copyTree($root . '/templates', $tmp . '/templates');
        $contractDir = $tmp . '/contract';
        if (!mkdir($contractDir, 0777, true) && !is_dir($contractDir)) {
            $this->fail("cannot create {$contractDir}");
        }
        if (!copy($root . '/' . ComponentsContract::CONTRACT_PATH, $tmp . '/' . ComponentsContract::CONTRACT_PATH)) {
            $this->fail('cannot copy ' . ComponentsContract::CONTRACT_PATH);
        }
    }

    /**
     * The drift of the temp tree, through the same public API the
     * checked-in comparison uses.
     *
     * @return list<string>
     */
    private function diffCopy(string $tmp): array
    {
        $actual = ComponentsContract::extract($tmp);
        $expected = ComponentsContract::load($tmp . '/' . ComponentsContract::CONTRACT_PATH);

        return ComponentsContract::diff($actual, $expected);
    }

    private function readFile(string $path): string
    {
        $content = file_get_contents($path);
        if ($content === false) {
            $this->fail("cannot read {$path}");
        }

        return $content;
    }

    private function writeFile(string $path, string $content): void
    {
        if (file_put_contents($path, $content) === false) {
            $this->fail("cannot write {$path}");
        }
    }

    private function copyTree(string $from, string $to): void
    {
        if (!is_dir($from)) {
            $this->fail("cannot copy missing directory {$from}");
        }
        if (!mkdir($to, 0777, true) && !is_dir($to)) {
            $this->fail("cannot create {$to}");
        }
        foreach (scandir($from) ?: [] as $entry) {
            if ($entry === '.' || $entry === '..') {
                continue;
            }
            $source = $from . '/' . $entry;
            if (is_dir($source)) {
                $this->copyTree($source, $to . '/' . $entry);
            } elseif (!copy($source, $to . '/' . $entry)) {
                $this->fail("cannot copy {$source}");
            }
        }
    }

    private function removeTree(string $path): void
    {
        if (!file_exists($path)) {
            return;
        }
        if (is_file($path)) {
            if (!unlink($path)) {
                $this->fail("cannot remove {$path}");
            }

            return;
        }
        foreach (scandir($path) ?: [] as $entry) {
            if ($entry === '.' || $entry === '..') {
                continue;
            }
            $this->removeTree($path . '/' . $entry);
        }
        if (!rmdir($path)) {
            $this->fail("cannot remove {$path}");
        }
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
