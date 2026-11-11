<?php

declare(strict_types=1);

namespace WayneState\Preflight\Tests;

use PHPUnit\Framework\TestCase;
use Symfony\Component\Yaml\Yaml;

/**
 * Holds two practices for every component's jobs that used to be only written
 * down. BEST_PRACTICES 2.9: each job a consumer gets sets `interruptible: true`
 * and a timeout of an hour or less, so a hung job frees its runner and a newer
 * push can cancel an old run. BEST_PRACTICES 5.1: no template holds a
 * credential, because every line of a CI file is readable by anyone with repo
 * access. A job without a timeout is a plane with no fuel gauge: it flies until
 * something else decides it has landed.
 */
final class TemplateJobsTest extends TestCase
{
    private const MAX_TIMEOUT_SECONDS = 3600;

    /** Top-level keys of a job document that are settings, not jobs. */
    private const NOT_JOBS = [
        'default', 'workflow', 'include', 'variables', 'stages', 'spec', 'image', 'services', 'cache',
        'before_script', 'after_script',
    ];

    /**
     * Inputs allowed to default to a literal credential, each with its reason.
     *
     * mysql56-migrate.db_password is the password of the job's own MySQL
     * service, which lives as long as the job and is reachable only from it.
     */
    private const LITERAL_CREDENTIAL_INPUTS = ['mysql56-migrate' => ['db_password']];

    /** Credential-named CI/CD variables a job may read: GitLab's own short-lived ones. */
    private const ALLOWED_CREDENTIAL_VARIABLES = ['CI_JOB_TOKEN', 'CI_DEPENDENCY_PROXY_PASSWORD'];

    /** Text that only a real token or key would carry. */
    private const SECRET_MARKERS = ['glpat-', 'ghp_', 'github_pat_', '-----BEGIN'];

    public function testEveryJobIsInterruptible(): void
    {
        $problems = [];
        foreach (self::templates() as $component => $template) {
            foreach (self::visibleJobs($template['jobs']) as $name => $job) {
                if (($job['interruptible'] ?? null) !== true) {
                    $problems[] = "{$component}: job {$name} does not set interruptible: true";
                }
            }
        }

        $this->assertSame([], $problems, "jobs a superseded pipeline cannot cancel:\n" . implode("\n", $problems));
    }

    public function testEveryJobHasATimeoutOfAnHourOrLess(): void
    {
        $problems = [];
        foreach (self::templates() as $component => $template) {
            foreach (self::visibleJobs($template['jobs']) as $name => $job) {
                $timeout = $job['timeout'] ?? null;
                if (! is_string($timeout) || trim($timeout) === '') {
                    $problems[] = "{$component}: job {$name} has no timeout";

                    continue;
                }
                $seconds = self::durationSeconds($timeout);
                if ($seconds === null) {
                    $problems[] = "{$component}: job {$name} has a timeout that does not parse: {$timeout}";
                } elseif ($seconds > self::MAX_TIMEOUT_SECONDS) {
                    $problems[] = "{$component}: job {$name} has a timeout over 1 hour: {$timeout}";
                }
            }
        }

        $this->assertSame([], $problems, "jobs that can hold a runner too long:\n" . implode("\n", $problems));
    }

    public function testNoTemplateHoldsACredential(): void
    {
        $problems = [];
        foreach (self::templates() as $component => $template) {
            foreach ($template['inputs'] as $input => $spec) {
                if (preg_match('/(password|passwd|token|secret|credential|private_key|api_key)/i', $input) !== 1) {
                    continue;
                }
                if (in_array($input, self::LITERAL_CREDENTIAL_INPUTS[$component] ?? [], true)) {
                    continue;
                }
                $default = is_array($spec) ? ($spec['default'] ?? null) : null;
                if ($default === null || $default === '') {
                    continue;
                }
                if (! is_string($default) || preg_match('/^[A-Z][A-Z0-9_]*$/', $default) !== 1) {
                    $problems[] = "{$component}: input {$input} defaults to a literal value, not a variable name";
                }
            }

            preg_match_all('/\$\{?([A-Z][A-Z0-9_]*)/', $template['jobText'], $matches);
            foreach (array_unique($matches[1]) as $variable) {
                if (preg_match('/(PASSWORD|PASSWD|TOKEN|SECRET|CREDENTIAL|PRIVATE_KEY|API_KEY)/', $variable) === 1
                    && ! in_array($variable, self::ALLOWED_CREDENTIAL_VARIABLES, true)) {
                    $problems[] = "{$component}: references credential variable {$variable}";
                }
            }

            foreach (self::SECRET_MARKERS as $marker) {
                if (str_contains($template['text'], $marker)) {
                    $problems[] = "{$component}: contains {$marker}";
                }
            }
        }

        $this->assertSame([], $problems, "credentials in the templates:\n" . implode("\n", $problems));
    }

    /**
     * Every template, keyed by its folder name.
     *
     * @return array<string, array{text: string, jobText: string, inputs: array<string, mixed>, jobs: array<string, mixed>}>
     */
    private static function templates(): array
    {
        $templates = [];
        foreach (glob(dirname(__DIR__) . '/templates/*/template.yml') ?: [] as $file) {
            $text = str_replace("\r\n", "\n", (string) file_get_contents($file));
            $inputs = [];
            $jobs = [];
            $jobText = [];
            foreach (self::splitDocuments($text) as $document) {
                $parsed = Yaml::parse($document);
                if (! is_array($parsed)) {
                    continue;
                }
                if (array_key_exists('spec', $parsed)) {
                    $spec = $parsed['spec'];
                    if (is_array($spec) && is_array($spec['inputs'] ?? null)) {
                        foreach ($spec['inputs'] as $name => $input) {
                            $inputs[(string) $name] = $input;
                        }
                    }

                    continue;
                }
                $jobText[] = $document;
                foreach ($parsed as $name => $job) {
                    $jobs[(string) $name] = $job;
                }
            }
            $templates[basename(dirname($file))] = [
                'text' => $text,
                'jobText' => implode("\n", $jobText),
                'inputs' => $inputs,
                'jobs' => $jobs,
            ];
        }

        self::assertNotSame([], $templates, 'no templates found');

        return $templates;
    }

    /**
     * The jobs a consumer gets, each merged with the jobs it extends.
     *
     * @param  array<string, mixed>  $jobs
     * @return array<string, array<mixed>>
     */
    private static function visibleJobs(array $jobs): array
    {
        $visible = [];
        foreach ($jobs as $name => $job) {
            if (str_starts_with($name, '.') || in_array($name, self::NOT_JOBS, true) || ! is_array($job)) {
                continue;
            }
            $visible[$name] = self::resolve($jobs, $name, []);
        }

        return $visible;
    }

    /**
     * One job with its extends chain applied, the job's own keys winning, like GitLab.
     *
     * @param  array<string, mixed>  $jobs
     * @param  list<string>  $seen
     * @return array<mixed>
     */
    private static function resolve(array $jobs, string $name, array $seen): array
    {
        $job = $jobs[$name] ?? null;
        if (! is_array($job) || in_array($name, $seen, true)) {
            return [];
        }
        $seen[] = $name;

        $parents = $job['extends'] ?? [];
        $parents = is_string($parents) ? [$parents] : (is_array($parents) ? $parents : []);

        $merged = [];
        foreach ($parents as $parent) {
            if (is_string($parent)) {
                $merged = array_replace($merged, self::resolve($jobs, $parent, $seen));
            }
        }
        unset($job['extends']);

        return array_replace($merged, $job);
    }

    /** Seconds in a GitLab duration such as "10m", "30 minutes" or "1h 30m"; null when it does not parse. */
    private static function durationSeconds(string $duration): ?int
    {
        $units = '(s|secs?|seconds?|m|mins?|minutes?|h|hrs?|hours?)';
        $part = '(\d+)\s*' . $units;
        if (preg_match('/^\s*(' . $part . '\s*)+$/i', $duration) !== 1) {
            return null;
        }

        preg_match_all('/' . $part . '/i', $duration, $matches, PREG_SET_ORDER);
        $seconds = 0;
        foreach ($matches as $match) {
            $unit = strtolower($match[2]);
            $seconds += (int) $match[1] * match (true) {
                str_starts_with($unit, 'h') => 3600,
                str_starts_with($unit, 'm') => 60,
                default => 1,
            };
        }

        return $seconds;
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
