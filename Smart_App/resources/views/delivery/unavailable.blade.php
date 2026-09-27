<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Delivery link unavailable</title>
    <style>
        body {
            font-family: system-ui, sans-serif;
            max-width: 28rem;
            margin: 3rem auto;
            padding: 0 1.1rem;
            line-height: 1.5;
            color: #12241C;
        }
        h1 { font-size: 1.35rem; }
        p { color: #4A6358; }
    </style>
</head>
<body>
    <h1>This delivery link is no longer available</h1>
    @if ($expired)
        <p>It has expired. Ask the shop to share a new link from the Water Delivery app.</p>
    @else
        <p>The link may be incorrect or was removed. Ask the shop to share a new one from the Water Delivery app.</p>
    @endif
</body>
</html>
