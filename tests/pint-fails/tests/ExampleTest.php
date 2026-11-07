<?php

declare(strict_types=1);

use PHPUnit\Framework\Assert;
use PHPUnit\Framework\TestCase;

final class ExampleTest extends TestCase
{
    public function test_one_plus_one() : void
    {
        $sum=1+1;
        $this->assertSame(2,$sum);
    }
}
