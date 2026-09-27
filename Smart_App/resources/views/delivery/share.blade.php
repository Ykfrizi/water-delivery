<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="robots" content="noindex, nofollow">
    <title>Delivery — {{ $order->order_number }}</title>
    <style>
        :root {
            --green: #0E6B4F;
            --green-dark: #0A4F3B;
            --mint: #E8F5E9;
            --ink: #12241C;
            --muted: #4A6358;
            --line: #D7E5DE;
            --bg: #F4F7F5;
            --white: #FFFFFF;
            --warn: #B45309;
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
            background: var(--bg);
            color: var(--ink);
            line-height: 1.45;
        }
        .wrap { max-width: 32rem; margin: 0 auto; padding: 1rem 1rem 2.5rem; }
        header {
            background: linear-gradient(160deg, var(--green-dark), var(--green));
            color: #fff;
            border-radius: 1.1rem;
            padding: 1.15rem 1.2rem 1.25rem;
        }
        header p { margin: 0.2rem 0 0; opacity: 0.88; font-size: 0.92rem; }
        h1 { margin: 0; font-size: 1.35rem; letter-spacing: -0.02em; }
        .card {
            background: var(--white);
            border-radius: 1rem;
            padding: 1rem 1.1rem;
            margin-top: 0.85rem;
            border: 1px solid var(--line);
        }
        .card h2 {
            margin: 0 0 0.7rem;
            font-size: 0.78rem;
            text-transform: uppercase;
            letter-spacing: 0.06em;
            color: var(--muted);
        }
        .kv { margin: 0.35rem 0; }
        .kv span { display: block; color: var(--muted); font-size: 0.78rem; }
        .kv strong { font-size: 1.02rem; }
        .item {
            display: flex;
            justify-content: space-between;
            gap: 0.75rem;
            padding: 0.55rem 0;
            border-bottom: 1px solid var(--line);
        }
        .item:last-child { border-bottom: 0; padding-bottom: 0; }
        .note {
            background: var(--mint);
            color: var(--green-dark);
            border-radius: 0.75rem;
            padding: 0.7rem 0.85rem;
            font-weight: 600;
            font-size: 0.95rem;
        }
        .actions {
            display: grid;
            gap: 0.65rem;
            margin-top: 1rem;
        }
        a.btn {
            display: block;
            text-align: center;
            text-decoration: none;
            border-radius: 0.85rem;
            padding: 0.9rem 1rem;
            font-weight: 700;
        }
        a.btn-primary { background: var(--green); color: #fff; }
        a.btn-ghost { background: var(--white); color: var(--green); border: 2px solid var(--green); }
        .meta { color: var(--muted); font-size: 0.82rem; margin-top: 1rem; text-align: center; }
        .pay { color: var(--warn); font-weight: 800; }
    </style>
</head>
<body>
    <div class="wrap">
        <header>
            <p>Water Delivery</p>
            <h1>{{ $shopName }}</h1>
            <p>Order {{ $order->order_number }}</p>
        </header>

        @if ($order->isPayOnDelivery())
            <p class="note" style="margin-top: 0.85rem;">Collect payment on delivery</p>
        @else
            <p class="note" style="margin-top: 0.85rem;">Already paid — do not collect extra cash</p>
        @endif

        <section class="card">
            <h2>Customer</h2>
            <p class="kv"><span>Name</span><strong>{{ $customerName }}</strong></p>
            @if ($customerPhone)
                <p class="kv"><span>Phone</span><strong>{{ $customerPhone }}</strong></p>
            @endif
            @if ($address !== '')
                <p class="kv"><span>Address</span><strong>{{ $address }}</strong></p>
            @endif
            @if ($latitude && $longitude)
                <p class="kv"><span>Pin</span><strong>{{ number_format($latitude, 5) }}, {{ number_format($longitude, 5) }}</strong></p>
            @endif
            @if ($order->notes)
                <p class="kv"><span>Notes</span><strong>{{ $order->notes }}</strong></p>
            @endif
        </section>

        <section class="card">
            <h2>Products</h2>
            @forelse ($order->orderItems as $item)
                <div class="item">
                    <div>
                        <strong>{{ $item->product_name }}</strong>
                        <div style="color: var(--muted); font-size: 0.88rem;">Qty {{ $item->quantity }}</div>
                    </div>
                    <div>{{ number_format((float) $item->line_total, 2) }} {{ $order->currency }}</div>
                </div>
            @empty
                <p>No line items on this order.</p>
            @endforelse
            <p class="kv" style="margin-top: 0.85rem;">
                <span>Total</span>
                <strong>{{ number_format((float) $order->total, 2) }} {{ $order->currency }}</strong>
            </p>
        </section>

        <div class="actions">
            @if ($customerPhone)
                <a class="btn btn-primary" href="tel:{{ preg_replace('/\s+/', '', $customerPhone) }}">Call customer</a>
            @endif
            @if ($mapsUrl)
                <a class="btn btn-ghost" href="{{ $mapsUrl }}" target="_blank" rel="noopener">Open in Maps</a>
            @endif
        </div>
        <p class="meta">This link expires {{ $expiresAt->timezone(config('app.timezone'))->format('D, j M Y g:i A') }}. Do not post it publicly.</p>
    </div>
</body>
</html>
