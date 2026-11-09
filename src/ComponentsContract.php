<?php

declare(strict_types=1);

namespace WayneState\Preflight;

use RuntimeException;
use Symfony\Component\Yaml\Exception\ParseException;
use Symfony\Component\Yaml\Yaml;

/**
 * The inputs contract: Preflight's own pre-flight checklist.
 *
 * Each component template promises its consumers that, inside a major version,
 * an input keeps its name, type and default, and a job keeps its name
 * (BEST_PRACTICES.md 1.4). This class reads that promise from
 * templates/<name>/template.yml and from contract/inputs.json, reports any
 * drift, and rewrites the contract when the change was made on purpose.
 */
final class ComponentsContract
{
    /** The contract file, relative to the repository root. */
    public const CONTRACT_PATH = 'contract/inputs.json';

    /**
     * Every component template, as the contract sees it: inputs in template
     * order, jobs resolved and sorted, components sorted by name.
     *
     * @param string $root The repository root.
     *
     * @return array{components: array<string, array{inputs: list<array{name: string, type?: string, default?: mixed, regex?: string}>, jobs: list<string>}>}
     */
    public static function extract(string $root): array
    {
        $components = [];

        foreach (glob($root . '/templates/*/template.yml') ?: [] as $file) {
            $name = basename(dirname($file));
            $documents = self::parseDocuments($file);

            $inputs = [];
            $jobDefault = '';
            $specDocument = $documents[0] ?? null;
            $spec = is_array($specDocument) ? ($specDocument['spec'] ?? null) : null;
            $rawInputs = is_array($spec) ? ($spec['inputs'] ?? null) : null;
            if (is_array($rawInputs)) {
                foreach ($rawInputs as $inputName => $input) {
                    $entry = ['name' => (string) $inputName];
                    if (is_array($input)) {
                        if (isset($input['type']) && is_scalar($input['type'])) {
                            $entry['type'] = (string) $input['type'];
                        }
                        if (array_key_exists('default', $input)) {
                            $entry['default'] = $input['default'];
                        }
                        if (isset($input['regex']) && is_string($input['regex'])) {
                            $entry['regex'] = $input['regex'];
                        }
                        if ($inputName === 'job_name' && isset($input['default']) && is_string($input['default'])) {
                            $jobDefault = $input['default'];
                        }
                    }
                    $inputs[] = $entry;
                }
            }

            $jobs = [];
            $jobDocument = $documents[1] ?? null;
            if (is_array($jobDocument)) {
                foreach (array_keys($jobDocument) as $job) {
                    $job = (string) $job;
                    // Hidden keys (a leading dot) are helpers, not jobs.
                    if (str_starts_with($job, '.')) {
                        continue;
                    }
                    $jobs[] = str_replace('$[[ inputs.job_name ]]', $jobDefault, $job);
                }
            }
            sort($jobs);

            $components[$name] = ['inputs' => $inputs, 'jobs' => $jobs];
        }

        ksort($components);

        return ['components' => $components];
    }

    /**
     * The checked-in contract, decoded.
     *
     * @param string $path Absolute path to the contract file.
     *
     * @return array<string, mixed>
     */
    public static function load(string $path): array
    {
        $raw = file_get_contents($path);
        if ($raw === false) {
            throw new RuntimeException("cannot read {$path}");
        }

        $data = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($data) || array_is_list($data)) {
            throw new RuntimeException("{$path} must hold a JSON object");
        }

        $object = [];
        foreach ($data as $key => $value) {
            $object[(string) $key] = $value;
        }

        return $object;
    }

    /**
     * The drift between the templates and the contract, one line per finding,
     * in the wording tests/check-contract.sh uses.
     *
     * @param array{components: array<string, array{inputs: list<array{name: string, type?: string, default?: mixed, regex?: string}>, jobs: list<string>}>} $actual The templates.
     * @param array<string, mixed> $expected The contract file.
     *
     * @return list<string>
     */
    public static function diff(array $actual, array $expected): array
    {
        $actualComponents = $actual['components'];
        $expectedComponents = $expected['components'] ?? [];
        if (!is_array($expectedComponents)) {
            $expectedComponents = [];
        }

        $messages = [];
        foreach ($expectedComponents as $name => $expectedComponent) {
            $name = (string) $name;
            if (!isset($actualComponents[$name])) {
                $messages[] = "contract entry '{$name}' has no template at templates/{$name}/template.yml";
                continue;
            }
            if (!is_array($expectedComponent)) {
                $messages[] = "component '{$name}': the contract entry must be an object";
                continue;
            }
            $messages = array_merge($messages, self::diffComponent($name, $actualComponents[$name], $expectedComponent));
        }

        foreach (array_keys($actualComponents) as $name) {
            if (!isset($expectedComponents[$name])) {
                $messages[] = "template '{$name}' has no entry in contract/inputs.json";
            }
        }

        return $messages;
    }

    /**
     * The contract file rewritten from the current templates: the existing note
     * and component order are kept, new components join in alphabetical order.
     *
     * @param string $root The repository root.
     */
    public static function regenerate(string $root): string
    {
        $path = $root . '/' . self::CONTRACT_PATH;
        $note = null;
        $order = [];
        if (is_file($path)) {
            $existing = self::load($path);
            if (isset($existing['note']) && is_string($existing['note'])) {
                $note = $existing['note'];
            }
            $components = $existing['components'] ?? null;
            if (is_array($components)) {
                $order = array_map('strval', array_keys($components));
            }
        }

        return self::render(self::extract($root), $note, $order);
    }

    /**
     * The contract bytes: two-space indent, input objects inline, jobs inline,
     * the same shape contract/inputs.json has been reviewed in.
     *
     * @param array{components: array<string, array{inputs: list<array{name: string, type?: string, default?: mixed, regex?: string}>, jobs: list<string>}>} $structure The extracted templates.
     * @param string|null $note The note to keep at the top of the file.
     * @param list<string> $componentOrder The order to keep; unknown names are dropped, missing ones appended sorted.
     */
    public static function render(array $structure, ?string $note = null, array $componentOrder = []): string
    {
        $components = $structure['components'];
        $ordered = self::orderedNames($components, $componentOrder);

        $lines = ['{'];
        if ($note !== null) {
            $lines[] = '  "note": ' . self::jsonString($note) . ',';
        }
        $lines[] = '  "components": {';

        $count = count($ordered);
        foreach ($ordered as $index => $name) {
            $component = $components[$name];
            $last = $index === $count - 1;
            $lines[] = '    "' . $name . '": {';
            $lines[] = '      "inputs": [';
            $inputs = $component['inputs'];
            $inputCount = count($inputs);
            foreach ($inputs as $inputIndex => $input) {
                $lines[] = '        ' . self::inputInline($input) . ($inputIndex === $inputCount - 1 ? '' : ',');
            }
            $lines[] = '      ],';
            // Jobs is always the last key of a component, so no comma here; the comma belongs on the closing brace.
            $lines[] = '      "jobs": ' . self::inlineArray($component['jobs']);
            $lines[] = '    }' . ($last ? '' : ',');
        }

        $lines[] = '  }';
        $lines[] = '}';

        return implode("\n", $lines) . "\n";
    }

    /**
     * @param array{inputs: list<array{name: string, type?: string, default?: mixed, regex?: string}>, jobs: list<string>} $actual
     * @param array<string, mixed> $expected
     *
     * @return list<string>
     */
    private static function diffComponent(string $name, array $actual, array $expected): array
    {
        $actualInputs = [];
        foreach ($actual['inputs'] as $input) {
            $actualInputs[(string) $input['name']] = $input;
        }

        $expectedInputs = [];
        $rawExpectedInputs = $expected['inputs'] ?? [];
        if (is_array($rawExpectedInputs)) {
            foreach ($rawExpectedInputs as $input) {
                if (is_array($input) && isset($input['name']) && is_string($input['name'])) {
                    $expectedInputs[$input['name']] = $input;
                }
            }
        }

        $messages = [];
        foreach (array_keys($expectedInputs) as $inputName) {
            if (!isset($actualInputs[$inputName])) {
                $messages[] = "component '{$name}': missing input: {$inputName}";
            }
        }
        foreach (array_keys($actualInputs) as $inputName) {
            if (!isset($expectedInputs[$inputName])) {
                $messages[] = "component '{$name}': unexpected input: {$inputName}";
            }
        }

        $actualJobs = $actual['jobs'];
        $expectedJobs = [];
        $rawExpectedJobs = $expected['jobs'] ?? [];
        if (is_array($rawExpectedJobs)) {
            foreach ($rawExpectedJobs as $job) {
                if (is_string($job)) {
                    $expectedJobs[] = $job;
                }
            }
        }
        foreach ($expectedJobs as $job) {
            if (!in_array($job, $actualJobs, true)) {
                $messages[] = "component '{$name}': missing job: {$job}";
            }
        }
        foreach ($actualJobs as $job) {
            if (!in_array($job, $expectedJobs, true)) {
                $messages[] = "component '{$name}': unexpected job: {$job}";
            }
        }

        foreach (array_intersect_key($actualInputs, $expectedInputs) as $inputName => $actualInput) {
            $expectedInput = $expectedInputs[$inputName];
            $actualType = $actualInput['type'] ?? null;
            $expectedType = $expectedInput['type'] ?? null;
            if ($actualType !== $expectedType) {
                $messages[] = "component '{$name}': input {$inputName}: type is " . self::displayType($actualType) . ', contract says ' . self::displayType($expectedType);
            }
            $hasActualDefault = array_key_exists('default', $actualInput);
            $hasExpectedDefault = array_key_exists('default', $expectedInput);
            if ($hasActualDefault !== $hasExpectedDefault || ($hasActualDefault && $actualInput['default'] !== $expectedInput['default'])) {
                $messages[] = "component '{$name}': input {$inputName}: default is " . self::displayDefault($hasActualDefault ? $actualInput['default'] : null) . ', contract says ' . self::displayDefault($hasExpectedDefault ? $expectedInput['default'] : null);
            }
        }

        return $messages;
    }

    /**
     * The component order for render(): the given order first (names that still
     * exist, duplicates dropped), then every remaining name alphabetically.
     *
     * @param array<string, array{inputs: list<array{name: string, type?: string, default?: mixed, regex?: string}>, jobs: list<string>}> $components
     * @param list<string> $componentOrder
     *
     * @return list<string>
     */
    private static function orderedNames(array $components, array $componentOrder): array
    {
        $ordered = [];
        foreach ($componentOrder as $name) {
            $name = (string) $name;
            if (isset($components[$name]) && !in_array($name, $ordered, true)) {
                $ordered[] = $name;
            }
        }
        $remaining = array_diff(array_keys($components), $ordered);
        sort($remaining);

        return array_merge($ordered, $remaining);
    }

    /**
     * One input object on a single line, keys in the order name, type, default,
     * regex; absent keys stay absent.
     *
     * @param array{name: string, type?: string, default?: mixed, regex?: string} $input
     */
    private static function inputInline(array $input): string
    {
        $parts = ['"name": ' . self::jsonString($input['name'])];
        if (isset($input['type'])) {
            $parts[] = '"type": ' . self::jsonString($input['type']);
        }
        if (array_key_exists('default', $input)) {
            $parts[] = '"default": ' . self::value($input['default']);
        }
        if (isset($input['regex'])) {
            $parts[] = '"regex": ' . self::jsonString($input['regex']);
        }

        return '{ ' . implode(', ', $parts) . ' }';
    }

    /**
     * A value in the compact JSON form the contract file uses: strings quoted,
     * arrays inline, nothing escaped that does not need it.
     */
    private static function value(mixed $value): string
    {
        if (is_array($value)) {
            return self::inlineArray(array_values($value));
        }

        return json_encode($value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
    }

    /**
     * @param list<mixed> $values
     */
    private static function inlineArray(array $values): string
    {
        $parts = array_map(
            static fn(mixed $value): string => self::value($value),
            $values,
        );

        return '[' . implode(', ', $parts) . ']';
    }

    private static function jsonString(string $value): string
    {
        return json_encode($value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
    }

    /** A type for a message: the plain word, or null when absent. */
    private static function displayType(mixed $value): string
    {
        return is_string($value) ? $value : 'null';
    }

    /** A default for a message: its JSON form, or null when absent. */
    private static function displayDefault(mixed $value): string
    {
        return $value === null ? 'null' : self::value($value);
    }

    /**
     * Symfony's YAML parser does not parse multi-document streams, so split on
     * top-level document markers before parsing each document separately.
     *
     * @param string $path Absolute path to a template file.
     *
     * @return list<array<string, mixed>>
     */
    private static function parseDocuments(string $path): array
    {
        $content = file_get_contents($path);
        if ($content === false) {
            throw new RuntimeException("cannot read {$path}");
        }

        $documents = [];
        foreach (self::splitDocuments($content) as $document) {
            try {
                $parsed = Yaml::parse($document);
            } catch (ParseException $exception) {
                throw new RuntimeException("invalid YAML in {$path}: " . $exception->getMessage(), 0, $exception);
            }
            if (is_array($parsed)) {
                $documents[] = $parsed;
            }
        }

        return $documents;
    }

    /**
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
            static fn(string $document): bool => self::hasYamlContent($document),
        ));
    }

    private static function hasYamlContent(string $document): bool
    {
        foreach (explode("\n", $document) as $line) {
            $trimmed = trim($line);
            if ($trimmed !== '' && !str_starts_with($trimmed, '#')) {
                return true;
            }
        }

        return false;
    }
}
