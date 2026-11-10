<?php

declare(strict_types=1);

namespace WayneState\Preflight\Tests;

use PHPUnit\Framework\TestCase;
use WayneState\Preflight\ComponentsContract;

/**
 * docs/guides/network-egress.md lists every host a Preflight job reaches
 * (BEST_PRACTICES 5.4), so a runner with a locked-down network can allow just
 * those. This test keeps the page honest: every component has a row, every
 * https:// host a template fetches from is named, and every registry host a
 * default image comes from is named. A new download has to file its flight
 * plan before it takes off.
 */
final class DocsEgressTest extends TestCase
{
    private const PAGE = 'docs/guides/network-egress.md';

    /** Links a job prints for people to read, never fetched by the job. */
    private const NOT_FETCHED = ['www.w3.org'];

    public function testEveryComponentHasARow(): void
    {
        $root = dirname(__DIR__);
        $page = (string) file_get_contents($root . '/' . self::PAGE);
        $contract = ComponentsContract::load($root . '/' . ComponentsContract::CONTRACT_PATH);

        $missing = [];
        foreach (array_keys($contract['components']) as $component) {
            if (! str_contains($page, '| `' . $component . '` |')) {
                $missing[] = (string) $component;
            }
        }

        $this->assertSame([], $missing, 'components with no row in ' . self::PAGE . ': ' . implode(', ', $missing));
    }

    public function testEveryFetchedHostIsNamed(): void
    {
        $root = dirname(__DIR__);
        $page = (string) file_get_contents($root . '/' . self::PAGE);

        $missing = [];
        foreach (glob($root . '/templates/*/template.yml') ?: [] as $file) {
            $component = basename(dirname($file));
            foreach (self::fetchedHosts((string) file_get_contents($file)) as $host) {
                if (! str_contains($page, '`' . $host . '`') && ! str_contains($page, ' ' . $host . ' ')) {
                    $missing[] = "{$component}: {$host}";
                }
            }
        }

        $this->assertSame([], $missing, 'hosts the templates fetch from that ' . self::PAGE . " does not name:\n" . implode("\n", $missing));
    }

    public function testEveryImageRegistryIsNamed(): void
    {
        $root = dirname(__DIR__);
        $page = (string) file_get_contents($root . '/' . self::PAGE);
        $contract = ComponentsContract::load($root . '/' . ComponentsContract::CONTRACT_PATH);

        $missing = [];
        foreach ($contract['components'] as $component => $spec) {
            foreach ($spec['inputs'] as $input) {
                if (! in_array($input['name'], ['image', 'service_image'], true) || ! isset($input['default']) || ! is_string($input['default'])) {
                    continue;
                }
                // Docker's rule: in a name with a slash, a first segment with a
                // dot or a port is a registry host. Anything else (php:8.4-cli,
                // renovate/renovate) is a Docker Hub image behind image_prefix.
                $parts = explode('/', $input['default']);
                $first = $parts[0];
                if (count($parts) < 2 || (! str_contains($first, '.') && ! str_contains($first, ':'))) {
                    continue;
                }
                if (! str_contains($page, '`' . $first . '`')) {
                    $missing[] = "{$component}: {$first}";
                }
            }
        }

        $this->assertSame([], $missing, 'image registries that ' . self::PAGE . " does not name:\n" . implode("\n", $missing));
    }

    /**
     * The https:// hosts in a template, less the ones it only prints.
     *
     * @return list<string>
     */
    private static function fetchedHosts(string $yaml): array
    {
        preg_match_all('#https://([A-Za-z0-9.-]+\.[A-Za-z]{2,})#', $yaml, $m);
        $hosts = array_values(array_unique($m[1]));

        return array_values(array_filter(
            $hosts,
            static fn(string $h): bool => ! in_array($h, self::NOT_FETCHED, true)
                && ! str_starts_with($h, 'docs.gitlab.com')
                && ! str_contains($h, 'example'),
        ));
    }
}
