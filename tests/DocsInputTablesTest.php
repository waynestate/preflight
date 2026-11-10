<?php

declare(strict_types=1);

namespace WayneState\Preflight\Tests;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;
use WayneState\Preflight\ComponentsContract;

/**
 * The input tables in the docs say what contract/inputs.json says.
 *
 * Every component is documented three times: its section of README.md, its
 * section of docs/reference/components.md, and its own guide,
 * docs/guides/component-<name>.md. Each carries a table of the component's
 * inputs. This test reads the contract (which the contract test keeps equal
 * to the templates) and fails when a table is missing, misses an input, lists
 * one the component no longer has, or gives it the wrong type or default.
 * The flight manual has to match the airplane, not last year's airplane.
 */
final class DocsInputTablesTest extends TestCase
{
    /**
     * @return iterable<string, array{string, string, string}>
     */
    public static function documents(): iterable
    {
        $root = dirname(__DIR__);
        $contract = ComponentsContract::load($root . '/' . ComponentsContract::CONTRACT_PATH);

        foreach (array_map('strval', array_keys($contract['components'])) as $component) {
            yield $component . ' in README.md' => [$component, 'README.md', '### ' . $component];
            yield $component . ' in the reference' => [$component, 'docs/reference/components.md', '## ' . $component];
            yield $component . ' guide' => [$component, 'docs/guides/component-' . $component . '.md', '## Inputs'];
        }
    }

    #[DataProvider('documents')]
    public function testTheInputTableMatchesTheContract(string $component, string $document, string $heading): void
    {
        $root = dirname(__DIR__);
        $contract = ComponentsContract::load($root . '/' . ComponentsContract::CONTRACT_PATH);
        $inputs = $contract['components'][$component]['inputs'];

        $path = $root . '/' . $document;
        $this->assertFileExists($path, "{$component}: {$document} is missing");
        $markdown = (string) file_get_contents($path);

        $rows = self::tableRows($markdown, $heading);
        $this->assertNotNull($rows, "{$component}: {$document} has no \"{$heading}\" section with an input table");

        $messages = [];
        $expected = [];
        foreach ($inputs as $input) {
            $name = $input['name'];
            $expected[$name] = true;
            if (! isset($rows[$name])) {
                $messages[] = "missing input: {$name}";

                continue;
            }
            [$type, $default] = $rows[$name];
            if (isset($input['type']) && $type !== $input['type']) {
                $messages[] = "input {$name}: type is \"{$type}\", contract says \"{$input['type']}\"";
            }
            if (array_key_exists('default', $input) && ! self::sameDefault($default, $input['default'])) {
                $messages[] = "input {$name}: default is {$default}, contract says " . self::render($input['default']);
            }
        }
        foreach (array_keys($rows) as $name) {
            if (! isset($expected[$name])) {
                $messages[] = "unexpected input: {$name}";
            }
        }

        $this->assertSame([], $messages, implode("\n", array_merge(
            array_map(static fn(string $m): string => "component '{$component}' in {$document}: {$m}", $messages),
            ['Fix the table under "' . $heading . '" so it matches contract/inputs.json (the templates).'],
        )));
    }

    /**
     * The input rows of the first table under a heading, keyed by input name.
     *
     * The section runs from the heading to the next heading of the same or a
     * higher level. A row is "| `name` | type | default | ... |".
     *
     * @return array<string, array{string, string}>|null
     */
    private static function tableRows(string $markdown, string $heading): ?array
    {
        $lines = preg_split('/\R/', $markdown) ?: [];
        $level = strspn($heading, '#');
        $inSection = false;
        $inFence = false;
        $rows = null;

        foreach ($lines as $line) {
            if (str_starts_with($line, '```')) {
                $inFence = ! $inFence;

                continue;
            }
            if ($inFence) {
                continue;
            }
            if (preg_match('/^(#+) /', $line, $m) === 1) {
                if ($inSection && strlen($m[1]) <= $level) {
                    break;
                }
                if (rtrim($line) === $heading) {
                    $inSection = true;
                }

                continue;
            }
            if (! $inSection) {
                continue;
            }
            if (preg_match('/^\|\s*`([A-Za-z0-9_]+)`\s*\|\s*([a-z]+)\s*\|\s*(.*?)\s*\|/', $line, $m) === 1) {
                $rows ??= [];
                $rows[$m[1]] = [$m[2], $m[3]];
            } elseif ($rows !== null && ! str_starts_with($line, '|')) {
                break;
            }
        }

        return $rows;
    }

    private static function sameDefault(string $cell, mixed $default): bool
    {
        if (preg_match('/^`(.*)`$/', $cell, $m) === 1) {
            $cell = $m[1];
        }
        if (is_array($default)) {
            return json_decode($cell, true) === $default;
        }
        if (is_bool($default)) {
            return $cell === ($default ? 'true' : 'false');
        }
        if ($default === '') {
            return $cell === '""';
        }
        // A string default may be quoted to show it is a string ("0", "null").
        if (is_string($default) && $cell === json_encode($default, JSON_UNESCAPED_SLASHES)) {
            return true;
        }

        return is_scalar($default) && $cell === (string) $default;
    }

    private static function render(mixed $default): string
    {
        if (is_array($default)) {
            return '`' . json_encode($default, JSON_UNESCAPED_SLASHES) . '`';
        }
        if (is_bool($default)) {
            return '`' . ($default ? 'true' : 'false') . '`';
        }
        if ($default === '') {
            return '`""`';
        }

        return '`' . (is_scalar($default) ? (string) $default : json_encode($default)) . '`';
    }
}
