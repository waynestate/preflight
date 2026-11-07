<?php

declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class ExampleTest extends TestCase
{
    public function test_one_plus_one(): void
    {
        $this->assertSame(2, 1 + 1);
    }

    public function test_type_error(): void
    {
        $this->assertSame(3, add_numbers('two'));
    }
}

function add_numbers(int $a): int
{
    return $a + 1;
}
