<?php

declare(strict_types=1);

namespace WayneState\Preflight;

/**
 * Runs the lint fixtures. Each directory under tests/lint-fixtures is one case:
 * its .yml files are linted, and its expected file states the exit code and
 * output substrings that must (or must not) appear.
 */
final class LintTestRunner
{
    public function __construct(private readonly string $root) {}

    public function run(): int
    {
        $fixtureDir = $this->root . '/tests/lint-fixtures';
        if (!is_dir($fixtureDir)) {
            fwrite(STDERR, 'Missing tests/lint-fixtures' . PHP_EOL);
            return 1;
        }

        $cases = glob($fixtureDir . '/*', GLOB_ONLYDIR) ?: [];
        sort($cases);

        if ($cases === []) {
            fwrite(STDERR, 'No lint fixtures found' . PHP_EOL);
            return 1;
        }

        $failures = 0;
        foreach ($cases as $caseDir) {
            $case = basename($caseDir);
            $result = $this->runCase($caseDir);

            if ($result['ok']) {
                fwrite(STDOUT, "PASS $case" . PHP_EOL);
                continue;
            }

            $failures++;
            fwrite(STDOUT, "FAIL $case" . PHP_EOL);
            foreach ($result['problems'] as $problem) {
                fwrite(STDOUT, "  $problem" . PHP_EOL);
            }
        }

        return $failures === 0 ? 0 : 1;
    }

    /**
     * @return array{ok: bool, problems: list<string>}
     */
    private function runCase(string $caseDir): array
    {
        $expectedFile = $caseDir . '/expected';
        if (!is_file($expectedFile)) {
            return ['ok' => false, 'problems' => ['missing expected file']];
        }

        $lines = file($expectedFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
        if ($lines === []) {
            return ['ok' => false, 'problems' => ['expected file is empty']];
        }

        $expectedExit = (int) trim(array_shift($lines));

        $yamlFiles = glob($caseDir . '/*.yml') ?: [];
        sort($yamlFiles);
        if ($yamlFiles === []) {
            return ['ok' => false, 'problems' => ['no .yml fixture files']];
        }

        $allowlist = $caseDir . '/lint-allow.yml';
        $linter = new TemplateLinter($caseDir);
        $findings = $linter->lintFiles(
            $yamlFiles,
            is_file($allowlist) ? $allowlist : null,
            $caseDir,
        );

        $actualExit = 0;
        foreach ($findings as $finding) {
            if ($finding['severity'] === 'error') {
                $actualExit = 1;
                break;
            }
        }

        $output = implode("\n", $linter->formatFindings($findings));
        $problems = [];

        if ($actualExit !== $expectedExit) {
            $problems[] = "exit: expected $expectedExit, got $actualExit";
        }

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '') {
                continue;
            }

            if (str_starts_with($line, '!')) {
                $forbidden = substr($line, 1);
                if ($forbidden !== '' && str_contains($output, $forbidden)) {
                    $problems[] = "forbidden output found: $forbidden";
                }
                continue;
            }

            if (!str_contains($output, $line)) {
                $problems[] = "missing expected output: $line";
            }
        }

        return ['ok' => $problems === [], 'problems' => $problems];
    }
}
