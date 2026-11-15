<?php

declare(strict_types=1);

namespace WayneState\Preflight\Tests;

use PHPUnit\Framework\TestCase;

/**
 * The front page is where most people copy their include lines from, and nothing tied it to the
 * release: 0.9.0 shipped while site/index.html still handed out 0.8.0's commit in the quick start,
 * every placard, the flight plan and the GitHub workflow, and the README art said 0.8.0 too.
 *
 * The rule this test holds:
 *
 * - Every Preflight pin on the page (a `component:` include or the reusable workflow's `uses:`)
 *   names the same full commit SHA and the same tag in its comment. Call that tag T.
 * - Every placard tag reads "in T", and the README art kit's COMPONENT_TAG is T.
 * - The README pins the same commit and tag: the release flow moves the README first, so a page
 *   left behind fails here.
 * - T is the newest release in CHANGELOG.md (its first `## x.y.z` heading, the same heading the
 *   docs builder stamps into the brand badge) or, on the release commit itself, the one before:
 *   that commit cannot pin its own SHA, so the page moves in the next commit.
 * - When git can see the tags, T's commit must be the tag's commit, and once the newest release's
 *   tag sits on an older commit than HEAD, T must be that release.
 *
 * Old releases may still be named in prose (a placard line that says "since 0.5.0", the log of
 * amendments); only pins and placard tags are held to T. A pilot who reads last month's checklist
 * still takes off, just not with this month's airplane.
 */
final class FrontPagePinsTest extends TestCase
{
    private const PAGE = 'site/index.html';

    private const ART_KIT = 'scripts/readme-art/build.mjs';

    /** A Preflight include or workflow reference, its ref, and the tag in its trailing comment. */
    private const PIN = '~(?:enterprise-apps/preflight/[a-z0-9-]+|waynestate/preflight/\.github/workflows/[A-Za-z0-9._-]+)@([^\s<]+)(?:[ \t]+\#[ \t]*([^\s<]+))?~';

    public function testThePagePinsOneCommitAndOneTag(): void
    {
        $pins = self::pins(self::read(self::PAGE));
        $this->assertNotSame([], $pins, self::PAGE . ' has no Preflight pins; the pattern in this test no longer matches the page');

        $problems = [];
        foreach ($pins as [$ref, $tag]) {
            if (preg_match('/^[0-9a-f]{40}$/', $ref) !== 1) {
                $problems[] = "pinned to {$ref}, not a full commit SHA";
            }
            if ($tag === '') {
                $problems[] = "{$ref} has no tag in a comment";
            }
        }
        $distinct = array_values(array_unique(array_map(static fn(array $p): string => $p[0] . ' # ' . $p[1], $pins)));
        if (count($distinct) > 1) {
            $problems[] = 'more than one commit or tag pinned: ' . implode(', ', $distinct);
        }

        $this->assertSame([], $problems, self::PAGE . ":\n" . implode("\n", $problems));
    }

    public function testPlacardsAndArtNameThePinnedTag(): void
    {
        [, $tag] = self::pagePin();

        $problems = [];
        preg_match_all('~<p class="placard__tag[^"]*">\s*([^<]*?)\s*</p>~', self::read(self::PAGE), $m);
        $this->assertNotSame([], $m[1], self::PAGE . ' has no placard tags; the pattern in this test no longer matches the page');
        foreach ($m[1] as $placard) {
            if (strtolower($placard) !== "in {$tag}") {
                $problems[] = self::PAGE . ": a placard reads \"{$placard}\", expected \"in {$tag}\"";
            }
        }

        if (preg_match('/^const COMPONENT_TAG = "([^"]+)";/m', self::read(self::ART_KIT), $art) !== 1) {
            $problems[] = self::ART_KIT . ': no COMPONENT_TAG line';
        } elseif ($art[1] !== $tag) {
            $problems[] = self::ART_KIT . ": COMPONENT_TAG is {$art[1]}, the page pins {$tag}";
        }

        $this->assertSame([], $problems, implode("\n", $problems));
    }

    public function testThePagePinsWhatTheReadmePins(): void
    {
        [$sha, $tag] = self::pagePin();

        $readme = array_values(array_unique(array_map(
            static fn(array $p): string => $p[0] . ' # ' . $p[1],
            array_filter(self::pins(self::read('README.md')), static fn(array $p): bool => preg_match('/^[0-9a-f]{40}$/', $p[0]) === 1),
        )));

        $this->assertCount(1, $readme, 'README.md should pin one commit and tag, found: ' . implode(', ', $readme));
        $this->assertSame($readme[0], "{$sha} # {$tag}", self::PAGE . ' pins a different commit or tag than README.md');
    }

    public function testThePinnedTagIsTheNewestRelease(): void
    {
        [$sha, $tag] = self::pagePin();

        preg_match_all('/^## (\d+\.\d+\.\d+)\b/m', self::read('CHANGELOG.md'), $m);
        $releases = $m[1];
        $this->assertNotSame([], $releases, 'CHANGELOG.md has no released `## x.y.z` heading');
        $newest = $releases[0];
        $previous = $releases[1] ?? null;

        $allowed = $previous === null ? [$newest] : [$newest, $previous];
        $this->assertContains($tag, $allowed, self::PAGE . " pins {$tag}; the newest release in CHANGELOG.md is {$newest}");

        $pinned = self::tagCommit($tag);
        if ($pinned !== null) {
            $this->assertSame($pinned, $sha, self::PAGE . " pins {$sha} as {$tag}, but tag {$tag} is commit {$pinned}");
        }

        $newestCommit = self::tagCommit($newest);
        $head = self::git(['rev-parse', '--verify', '--quiet', 'HEAD']);
        if ($tag !== $newest && $newestCommit !== null && $head !== null && $newestCommit !== $head) {
            $this->fail(self::PAGE . " still pins {$tag}; {$newest} was tagged at {$newestCommit} and HEAD has moved on. Pin {$newest}.");
        }
    }

    /** @return array{0: string, 1: string} the commit and tag every pin on the page shares */
    private static function pagePin(): array
    {
        $pins = self::pins(self::read(self::PAGE));
        if ($pins === []) {
            self::fail(self::PAGE . ' has no Preflight pins');
        }

        return $pins[0];
    }

    /** @return list<array{0: string, 1: string}> each pin's ref and comment tag ('' when there is none) */
    private static function pins(string $text): array
    {
        preg_match_all(self::PIN, $text, $m, PREG_SET_ORDER);

        return array_map(static fn(array $hit): array => [$hit[1], $hit[2] ?? ''], $m);
    }

    private static function read(string $relative): string
    {
        $path = dirname(__DIR__) . '/' . $relative;
        $text = @file_get_contents($path);
        if ($text === false) {
            self::fail("cannot read {$relative}");
        }

        return $text;
    }

    private static function tagCommit(string $tag): ?string
    {
        return self::git(['rev-parse', '--verify', '--quiet', 'refs/tags/' . $tag . '^{commit}']);
    }

    /**
     * Runs one read-only git command in the repo root. Null when git is missing, the folder is not
     * a checkout (a tarball, a shallow CI clone without tags) or the command fails: the checks that
     * need git then stand down and the README check carries the rule.
     *
     * @param  list<string>  $args
     */
    private static function git(array $args): ?string
    {
        $proc = @proc_open(
            ['git', ...$args],
            [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
            $pipes,
            dirname(__DIR__),
        );
        if (! is_resource($proc)) {
            return null;
        }
        fclose($pipes[0]);
        $out = trim((string) stream_get_contents($pipes[1]));
        fclose($pipes[1]);
        fclose($pipes[2]);

        return proc_close($proc) === 0 && preg_match('/^[0-9a-f]{40}$/', $out) === 1 ? $out : null;
    }
}
