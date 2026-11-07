<?php

// The portability fixture app: four routes, each built clean, plus one flaw
// at a time (FIXTURE_FLAW, set from the Dockerfile's FLAW build arg).
//
//   /up     200 for any Host (host-bound: only for APP_URL's host)
//   /       302 to the canonical home URL, built from APP_URL
//           (trusts-proxy: built from X-Forwarded-Host and -Proto instead)
//   /login  signs in the test user with a signed cookie keyed by APP_KEY, so
//           any replica can read it (file-sessions: PHP file sessions on the
//           replica's own disk); logs the sign-in to stderr
//           (file-logs: to storage/logs/app.log)
//   /me     200 with the signed-in user, 401 without one
//           (trusts-proxy: also believes X-Forwarded-User)
//
// Config comes from the environment only: APP_URL and APP_KEY. PHP's own
// warnings go to stderr with the other logs, never into a response.

ini_set('display_errors', 'stderr');

$flaw = getenv('FIXTURE_FLAW') ?: 'none';
$appUrl = getenv('APP_URL') ?: 'http://localhost:8080';
$appKey = getenv('APP_KEY') ?: '';
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

/** @param list<string> $headers */
function answer(int $status, string $body, array $headers = []): void
{
    http_response_code($status);
    header('Content-Type: text/plain');
    foreach ($headers as $header) {
        header($header);
    }
    echo $body, "\n";
}

function logLine(string $flaw, string $line): void
{
    if ($flaw === 'file-logs') {
        @mkdir('/app/storage/logs', 0775, true);
        file_put_contents('/app/storage/logs/app.log', $line . "\n", FILE_APPEND);

        return;
    }
    file_put_contents('php://stderr', $line . "\n");
}

function baseUrl(string $flaw, string $appUrl): string
{
    if ($flaw === 'trusts-proxy') {
        $scheme = $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? 'http';
        $host = $_SERVER['HTTP_X_FORWARDED_HOST'] ?? ($_SERVER['HTTP_HOST'] ?? 'localhost');

        return $scheme . '://' . $host;
    }

    return rtrim($appUrl, '/');
}

function signedUser(string $appKey): ?string
{
    $cookie = $_COOKIE['fixture_session'] ?? '';
    $parts = explode('.', $cookie, 2);
    if (count($parts) !== 2 || $appKey === '') {
        return null;
    }
    $user = base64_decode($parts[0], true);
    if ($user === false || ! hash_equals(hash_hmac('sha256', $user, $appKey), $parts[1])) {
        return null;
    }

    return $user;
}

function currentUser(string $flaw, string $appKey): ?string
{
    if ($flaw === 'trusts-proxy' && isset($_SERVER['HTTP_X_FORWARDED_USER'])) {
        return $_SERVER['HTTP_X_FORWARDED_USER'];
    }
    if ($flaw === 'file-sessions') {
        if (! isset($_COOKIE[session_name()])) {
            return null;
        }
        @mkdir('/app/storage/sessions', 0775, true);
        session_save_path('/app/storage/sessions');
        session_start();

        return $_SESSION['user'] ?? null;
    }

    return signedUser($appKey);
}

if ($path === '/up') {
    $own = parse_url($appUrl, PHP_URL_HOST);
    $asked = strtolower(explode(':', $_SERVER['HTTP_HOST'] ?? '')[0]);
    if ($flaw === 'host-bound' && $asked !== $own) {
        answer(400, 'unknown host');

        return;
    }
    answer(200, 'ok');

    return;
}

if ($path === '/') {
    $home = baseUrl($flaw, $appUrl) . '/home';
    answer(302, 'see ' . $home, ['Location: ' . $home]);

    return;
}

if ($path === '/login') {
    $user = 'portability';
    if ($flaw === 'file-sessions') {
        @mkdir('/app/storage/sessions', 0775, true);
        session_save_path('/app/storage/sessions');
        session_start();
        $_SESSION['user'] = $user;
    } else {
        $value = base64_encode($user) . '.' . hash_hmac('sha256', $user, $appKey);
        setcookie('fixture_session', $value, ['path' => '/', 'httponly' => true, 'samesite' => 'Lax']);
    }
    logLine($flaw, 'fixture: signed in user=' . $user);
    answer(200, 'signed in');

    return;
}

if ($path === '/me') {
    $user = currentUser($flaw, $appKey);
    if ($user === null) {
        answer(401, 'guest');

        return;
    }
    answer(200, 'user: ' . $user);

    return;
}

answer(404, 'not found');
