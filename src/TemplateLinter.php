<?php

declare(strict_types=1);

namespace WayneState\Preflight;

use FilesystemIterator;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use SplFileInfo;
use Symfony\Component\Yaml\Exception\ParseException;
use Symfony\Component\Yaml\Yaml;

/**
 * Preflight checks for the CI templates: read the checklist before engine start.
 *
 * The linter scans GitLab component templates and GitHub workflow files for
 * patterns that are unsafe in a shared CI environment. Warnings do not fail
 * the build; errors do.
 */
final class TemplateLinter
{
    /** @var array<string, true> */
    private array $seen = [];

    public function __construct(private readonly string $root) {}

    public function run(): int
    {
        $findings = $this->lintFiles(
            $this->defaultFiles(),
            $this->root . '/lint-allow.yml',
            $this->root,
        );

        return $this->report($findings);
    }

    /**
     * @return list<string> Absolute paths of the files this repository lints.
     */
    public function defaultFiles(): array
    {
        $files = [];

        $templates = $this->root . '/templates';
        if (is_dir($templates)) {
            $iterator = new RecursiveIteratorIterator(
                new RecursiveDirectoryIterator($templates, FilesystemIterator::SKIP_DOTS),
            );
            foreach ($iterator as $file) {
                if ($file instanceof SplFileInfo && $file->isFile() && str_ends_with($file->getPathname(), '.yml')) {
                    $files[] = $file->getPathname();
                }
            }
        }

        $workflows = $this->root . '/.github/workflows';
        if (is_dir($workflows)) {
            foreach (glob($workflows . '/*.yml') ?: [] as $file) {
                $files[] = $file;
            }
        }

        $files = array_values(array_unique($files));
        sort($files);

        return $files;
    }

    /**
     * @param list<string> $files
     * @return list<array{file: string, severity: string, rule: string, message: string}>
     */
    public function lintFiles(array $files, ?string $allowlistPath = null, ?string $baseDir = null): array
    {
        $this->seen = [];
        $findings = [];

        [$allowed, $allowlistFindings] = $this->loadAllowlist($allowlistPath);
        foreach ($allowlistFindings as $finding) {
            $findings[] = $finding;
        }

        foreach ($files as $file) {
            $relative = $this->relativePath($file, $baseDir);
            foreach ($this->parseYaml($file, $relative, $findings) as $document) {
                $this->checkComponentInputDefaults($document, $relative, $findings);
                $this->visit($document, $relative, [], $findings);
            }
        }

        $filtered = [];
        foreach ($findings as $finding) {
            if ($finding['file'] !== 'lint-allow.yml' && isset($allowed[$finding['file']][$finding['rule']])) {
                continue;
            }
            $filtered[] = $finding;
        }

        return $filtered;
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     * @return list<string>
     */
    public function formatFindings(array $findings): array
    {
        $lines = [];
        foreach ($findings as $finding) {
            $lines[] = sprintf(
                '%s: [%s] %s: %s',
                $finding['file'],
                strtolower($finding['severity']),
                $finding['rule'],
                $finding['message'],
            );
        }

        return $lines;
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function report(array $findings): int
    {
        foreach ($this->formatFindings($findings) as $line) {
            fwrite(STDOUT, $line . PHP_EOL);
        }

        $errors = 0;
        foreach ($findings as $finding) {
            if ($finding['severity'] === 'error') {
                $errors++;
            }
        }

        return $errors > 0 ? 1 : 0;
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     * @return list<mixed>
     */
    private function parseYaml(string $path, string $relative, array &$findings): array
    {
        if (!is_file($path)) {
            $this->addFinding($relative, 'error', 'file-missing', 'file not found: ' . $path, $findings);

            return [];
        }

        $content = file_get_contents($path);
        if ($content === false) {
            $this->addFinding($relative, 'error', 'yaml-invalid', 'file could not be read: ' . $path, $findings);

            return [];
        }

        $documents = [];
        foreach ($this->splitDocuments($content) as $document) {
            try {
                $parsed = Yaml::parse($document);
            } catch (ParseException $exception) {
                $this->addFinding($relative, 'error', 'yaml-invalid', $exception->getMessage(), $findings);

                return [];
            }

            if ($parsed !== null) {
                $documents[] = $parsed;
            }
        }

        return $documents;
    }

    /**
     * Symfony's YAML parser does not parse multi-document streams, so split on
     * top-level document markers before parsing each document separately.
     *
     * @return list<string>
     */
    private function splitDocuments(string $content): array
    {
        $documents = [];
        $current = [];

        foreach (explode("\n", $content) as $line) {
            if (preg_match('/^(?:---|\.\.\.)[ \t]*$/', $line)) {
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

    /**
     * @return array{0: array<string, array<string, list<string>>>, 1: list<array{file: string, severity: string, rule: string, message: string}>}
     */
    private function loadAllowlist(?string $path): array
    {
        $allowed = [];
        $findings = [];

        if ($path === null || !is_file($path)) {
            return [$allowed, $findings];
        }

        try {
            $data = Yaml::parseFile($path);
        } catch (ParseException $exception) {
            $this->addFinding('lint-allow.yml', 'error', 'allowlist-invalid', $exception->getMessage(), $findings);

            return [$allowed, $findings];
        }

        if ($data === null) {
            return [$allowed, $findings];
        }

        if (is_array($data) && isset($data['allow']) && is_array($data['allow'])) {
            $entries = $data['allow'];
        } elseif (is_array($data) && array_is_list($data)) {
            $entries = $data;
        } else {
            $this->addFinding(
                'lint-allow.yml',
                'error',
                'allowlist-invalid',
                'the allowlist must be a list of entries or a mapping with an allow: list',
                $findings,
            );

            return [$allowed, $findings];
        }

        if (!array_is_list($entries)) {
            $this->addFinding(
                'lint-allow.yml',
                'error',
                'allowlist-invalid',
                'allowlist entries must be a list',
                $findings,
            );

            return [$allowed, $findings];
        }

        foreach ($entries as $index => $entry) {
            $position = $index + 1;
            $file = is_array($entry) ? ($entry['file'] ?? null) : null;
            $rule = is_array($entry) ? ($entry['rule'] ?? null) : null;
            $reason = is_array($entry) ? ($entry['reason'] ?? null) : null;

            if (
                !is_array($entry)
                || array_is_list($entry)
                || !is_string($file)
                || trim($file) === ''
                || !is_string($rule)
                || trim($rule) === ''
                || !is_string($reason)
                || trim($reason) === ''
            ) {
                $this->addFinding(
                    'lint-allow.yml',
                    'error',
                    'allowlist-invalid',
                    "entry $position must have a file, a rule, and a non-empty reason",
                    $findings,
                );
                continue;
            }

            $normalizedFile = str_replace('\\', '/', $file);
            $allowed[trim($normalizedFile)][$rule][] = trim($reason);
        }

        return [$allowed, $findings];
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function checkComponentInputDefaults(mixed $document, string $file, array &$findings): void
    {
        if (!is_array($document)) {
            return;
        }

        $inputs = $document['spec']['inputs'] ?? null;
        if (!is_array($inputs)) {
            return;
        }

        foreach ($inputs as $name => $input) {
            if ($name !== 'image' || !is_array($input) || !is_string($input['default'] ?? null)) {
                continue;
            }

            $this->checkImageRef($input['default'], $file, $findings);
        }
    }

    /**
     * @param list<string> $path
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function visit(mixed $node, string $file, array $path, array &$findings): void
    {
        if (is_array($node)) {
            if (array_is_list($node)) {
                foreach ($node as $index => $value) {
                    $this->visit($value, $file, [...$path, (string) $index], $findings);
                }
                return;
            }

            foreach ($node as $key => $value) {
                $stringKey = (string) $key;
                $childPath = [...$path, $stringKey];
                $this->checkKey($stringKey, $value, $file, $findings);
                $this->visit($value, $file, $childPath, $findings);
            }
            return;
        }

        $this->checkScalar($node, $file, $findings);
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function checkKey(string $key, mixed $value, string $file, array &$findings): void
    {
        if ($key === 'privileged' && $value === true) {
            $this->addFinding($file, 'error', 'privileged', 'privileged: true is not allowed', $findings);
        }

        if ($key === 'uses' && is_string($value)) {
            $this->checkActionRef($value, $file, $findings);
        }

        if ($key === 'image') {
            $this->checkImageValue($value, $file, $findings);
        }

        if ($key === 'services') {
            $this->visitServiceValue($value, $file, $findings);
        }
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function checkImageValue(mixed $value, string $file, array &$findings): void
    {
        if (is_string($value)) {
            $this->checkImageRef($value, $file, $findings);
            return;
        }

        if (is_array($value) && !array_is_list($value) && is_string($value['name'] ?? null)) {
            $this->checkImageRef($value['name'], $file, $findings);
        }
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function checkActionRef(string $uses, string $file, array &$findings): void
    {
        $uses = trim($uses);
        if ($uses === '' || str_starts_with($uses, './')) {
            return;
        }

        $at = strrpos($uses, '@');
        if ($at === false) {
            $this->addFinding(
                $file,
                'error',
                'unpinned-action',
                "GitHub action reference is not pinned to a 40-character commit SHA: $uses",
                $findings,
            );
            return;
        }

        $ref = substr($uses, $at + 1);
        if (!preg_match('/^[a-f0-9]{40}$/i', $ref)) {
            $this->addFinding(
                $file,
                'error',
                'unpinned-action',
                "GitHub action reference is not pinned to a 40-character commit SHA: $uses",
                $findings,
            );
        }
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function checkImageRef(string $ref, string $file, array &$findings): void
    {
        $ref = trim($ref);
        if ($ref === '') {
            return;
        }

        // A value that is only a GitLab input interpolation or a CI variable is
        // resolved somewhere else; lint the resolved default instead.
        if (preg_match('/^\$\[\[.*\]\]$/', $ref) || preg_match('/^\$\{.*\}$/', $ref)) {
            return;
        }

        if (str_contains(strtolower($ref), 'kaniko')) {
            $this->addFinding($file, 'error', 'kaniko-image', "Kaniko image is not allowed: $ref", $findings);
        }

        $digest = null;
        $nameTag = $ref;
        if (str_contains($ref, '@')) {
            [$nameTag, $candidateDigest] = explode('@', $ref, 2);
            if (preg_match('/^[a-z0-9]+:[a-f0-9]{64}$/i', $candidateDigest)) {
                $digest = $candidateDigest;
            }
        }

        $tag = null;
        $lastSlash = strrpos($nameTag, '/');
        $lastColon = strrpos($nameTag, ':');
        if ($lastColon !== false && ($lastSlash === false || $lastColon > $lastSlash)) {
            $tag = substr($nameTag, $lastColon + 1);
        }

        if ($digest === null && $tag === null) {
            $this->addFinding(
                $file,
                'error',
                'image-no-tag',
                "Image reference has no tag or digest: $ref",
                $findings,
            );
        } elseif ($tag === 'latest') {
            $this->addFinding(
                $file,
                'error',
                'image-latest',
                "Image reference uses the latest tag: $ref",
                $findings,
            );
        } elseif ($digest === null) {
            $this->addFinding(
                $file,
                'warning',
                'image-no-digest',
                "Image reference is not pinned by digest: $ref",
                $findings,
            );
        }
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function visitServiceValue(mixed $node, string $file, array &$findings): void
    {
        if (is_string($node)) {
            $this->checkServiceRef($node, $file, $findings);
            return;
        }

        if (!is_array($node)) {
            return;
        }

        if (array_is_list($node)) {
            foreach ($node as $value) {
                $this->visitServiceValue($value, $file, $findings);
            }
            return;
        }

        foreach ($node as $key => $value) {
            $this->checkServiceRef((string) $key, $file, $findings);
            $this->visitServiceValue($value, $file, $findings);
        }
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function checkServiceRef(string $ref, string $file, array &$findings): void
    {
        $ref = trim($ref);
        if ($ref === '' || str_starts_with($ref, '$')) {
            return;
        }

        if (preg_match('#(?:^|/)docker:(?:dind|.+-dind)$#i', $ref)) {
            $this->addFinding(
                $file,
                'error',
                'dind-service',
                "Docker-in-Docker service is not allowed: $ref",
                $findings,
            );
        }

        if (str_contains(strtolower($ref), 'kaniko')) {
            $this->addFinding($file, 'error', 'kaniko-image', "Kaniko image is not allowed: $ref", $findings);
        }
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function checkScalar(mixed $node, string $file, array &$findings): void
    {
        if (is_string($node) && str_contains($node, 'docker.sock')) {
            $this->addFinding($file, 'error', 'docker-sock', 'references docker.sock', $findings);
        }
    }

    /**
     * @param list<array{file: string, severity: string, rule: string, message: string}> $findings
     */
    private function addFinding(string $file, string $severity, string $rule, string $message, array &$findings): void
    {
        $key = implode('|', [$file, $severity, $rule, $message]);
        if (isset($this->seen[$key])) {
            return;
        }

        $this->seen[$key] = true;
        $findings[] = [
            'file' => $file,
            'severity' => $severity,
            'rule' => $rule,
            'message' => $message,
        ];
    }

    private function relativePath(string $path, ?string $baseDir): string
    {
        $path = str_replace('\\', '/', $path);

        if ($baseDir !== null) {
            $base = rtrim(str_replace('\\', '/', $baseDir), '/');
            if ($base !== '' && str_starts_with($path, $base . '/')) {
                return substr($path, strlen($base) + 1);
            }
        }

        return $path;
    }
}
