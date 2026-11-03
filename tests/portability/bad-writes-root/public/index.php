<?php
// A tiny app for the portability fixture.
//
// It answers /up with 200 "ok" for any Host header, so the health check can
// use a foreign Host. Every other path writes to storage/ and answers 200,
// which proves the writable path is writable at request time too.
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

if ($path === '/up') {
    http_response_code(200);
    header('Content-Type: text/plain');
    echo 'ok';
    return;
}

file_put_contents(__DIR__ . '/../storage/last-hit.txt', date('c') . "\n", FILE_APPEND);
http_response_code(200);
header('Content-Type: text/plain');
echo 'hit';
