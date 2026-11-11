<?php

declare(strict_types=1);

namespace WayneState\Preflight\Tests;

use PHPUnit\Framework\TestCase;
use Symfony\Component\Yaml\Yaml;

/**
 * Preflight's own pipeline is the first consumer of every component it ships:
 * an include that passes an input the component's spec does not declare, or a
 * value its regex refuses, dies at pipeline creation, as php_advisory_version
 * "8.6-rc" did while the regex only allowed dots between parts. This test reads
 * every `component:` include in .gitlab-ci.yml that points at this project and
 * checks each input it gives against the spec.inputs of
 * templates/<name>/template.yml, so a value the docs recommend can never be
 * refused by the regex again. Values that contain $ (CI variables GitLab
 * expands at job time) are skipped.
 */
final class PipelineInputsTest extends TestCase
{
    public function testOwnPipelineInputsMatchTheComponentSpecs(): void
    {
        $problems = [];
        foreach (self::ownComponentIncludes() as $component => $inputs) {
            $spec = self::specInputs($component);
            if ($spec === null) {
                $problems[] = "{$component}: no spec.inputs found in templates/{$component}/template.yml";
                continue;
            }

            foreach ($inputs as $input => $value) {
                if (! array_key_exists($input, $spec)) {
                    $problems[] = "{$component}: input {$input} is not declared in its spec (value: " . self::show($value) . ')';
                    continue;
                }

                $regex = is_array($spec[$input]) ? ($spec[$input]['regex'] ?? null) : null;
                if (! is_string($regex) || $regex === '') {
                    continue;
                }

                foreach (self::scalars($value) as $scalar) {
                    if (str_contains($scalar, '$')) {
                        continue;
                    }
                    if (@preg_match('/' . $regex . '/', $scalar) !== 1) {
                        $problems[] = "{$component}: input {$input} value '{$scalar}' does not match the spec's regex {$regex}";
                    }
                }
            }
        }

        $this->assertSame([], $problems, "Preflight's own pipeline disagrees with its components:\n" . implode("\n", $problems));
    }

    /**
     * The includes of Preflight's own .gitlab-ci.yml that point at this
     * project, keyed by component name, each with the inputs it passes.
     *
     * @return array<string, array<string, mixed>>
     */
    private static function ownComponentIncludes(): array
    {
        $parsed = Yaml::parse((string) file_get_contents(dirname(__DIR__) . '/.gitlab-ci.yml'));
        if (! is_array($parsed)) {
            self::fail('.gitlab-ci.yml did not parse to a mapping');
        }

        $includes = [];
        foreach ((array) ($parsed['include'] ?? []) as $entry) {
            if (! is_array($entry) || ! is_string($entry['component'] ?? null)) {
                continue;
            }
            if (preg_match('%\$CI_PROJECT_PATH/([^/@\s]+)@%', $entry['component'], $match) !== 1) {
                continue;
            }
            $inputs = $entry['inputs'] ?? [];
            $includes[$match[1]] = is_array($inputs) ? $inputs : [];
        }

        self::assertNotSame([], $includes, 'no component includes of this project found in .gitlab-ci.yml');

        return $includes;
    }

    /**
     * The spec.inputs of the first YAML document of templates/<name>/template.yml, or null.
     *
     * @return array<string, mixed>|null
     */
    private static function specInputs(string $component): ?array
    {
        $file = dirname(__DIR__) . "/templates/{$component}/template.yml";
        if (! is_file($file)) {
            return null;
        }
        $text = str_replace("\r\n", "\n", (string) file_get_contents($file));
        foreach (self::splitDocuments($text) as $document) {
            $parsed = Yaml::parse($document);
            if (! is_array($parsed) || ! is_array($parsed['spec']['inputs'] ?? null)) {
                continue;
            }

            return $parsed['spec']['inputs'];
        }

        return null;
    }

    /**
     * The scalar strings of an input value, arrays flattened.
     *
     * @param  mixed  $value
     * @return list<string>
     */
    private static function scalars(mixed $value): array
    {
        if (is_array($value)) {
            $out = [];
            foreach ($value as $item) {
                $out = array_merge($out, self::scalars($item));
            }

            return $out;
        }
        if (is_bool($value)) {
            return [$value ? 'true' : 'false'];
        }
        if (is_scalar($value)) {
            return [(string) $value];
        }

        return [];
    }

    /**
     * A value for a failure message.
     *
     * @param  mixed  $value
     */
    private static function show(mixed $value): string
    {
        return json_encode($value, JSON_UNESCAPED_SLASHES) ?: 'null';
    }

    /**
     * The YAML documents of a template, split on "---" and "..." lines.
     *
     * @return list<string>
     */
    private static function splitDocuments(string $content): array
    {
        $documents = [];
        $current = [];
        foreach (explode("\n", $content) as $line) {
            if (preg_match('/^(?:---|\.\.\.)[ \t]*$/', $line) === 1) {
                $documents[] = implode("\n", $current);
                $current = [];

                continue;
            }
            $current[] = $line;
        }
        $documents[] = implode("\n", $current);

        return array_values(array_filter(
            $documents,
            static fn(string $document): bool => preg_match('/^[ \t]*[^#\s]/m', $document) === 1,
        ));
    }
}
