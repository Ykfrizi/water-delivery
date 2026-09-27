<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Payment complete</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 32rem; margin: 3rem auto; padding: 0 1rem; line-height: 1.5; }
        code { background: #f4f4f4; padding: 0.15rem 0.4rem; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>Payment received</h1>
    @if ($reference)
        <p>Reference: <code>{{ $reference }}</code></p>
        <p>Return to the app — it should call <strong>GET /api/v1/customer/payments/paystack/verify?reference={{ $reference }}</strong> with your login token.</p>
    @else
        <p>Return to the app and verify the payment using the reference from your order.</p>
    @endif
</body>
</html>
