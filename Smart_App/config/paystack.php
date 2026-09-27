<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Paystack keys (Dashboard → Settings → API Keys & Webhooks)
    |--------------------------------------------------------------------------
    */

    'secret_key' => env('PAYSTACK_SECRET_KEY'),
    'public_key' => env('PAYSTACK_PUBLIC_KEY'),

    /*
    |--------------------------------------------------------------------------
    | Default redirect after Paystack hosted checkout (customer's browser).
    | Do NOT use the webhook URL here. Webhook: /api/v1/payments/paystack/webhook
    |--------------------------------------------------------------------------
    */

    'callback_url' => env('PAYSTACK_CALLBACK_URL', rtrim((string) env('APP_URL', 'http://localhost'), '/').'/payment/callback'),

    /*
    |--------------------------------------------------------------------------
    | Default / merchant settlement currency (ISO 4217)
    |--------------------------------------------------------------------------
    | Must match a currency enabled on your Paystack business (e.g. GHS, NGN).
    */

    'currency' => strtoupper((string) env('PAYSTACK_CURRENCY', 'GHS')),

    /*
    |--------------------------------------------------------------------------
    | Paystack REST API base URL
    |--------------------------------------------------------------------------
    */

    'base_url' => env('PAYSTACK_BASE_URL', 'https://api.paystack.co'),

];
