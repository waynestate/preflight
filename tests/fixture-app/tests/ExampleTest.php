<?php

declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class ExampleTest extends TestCase
{
    public function testOnePlusOne(): void
    {
        $this->assertSame(2, 1 + 1);
    }
}
