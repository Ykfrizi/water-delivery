<?php

namespace App\Services\Paystack;

use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;

final class PaystackClient
{
    public function initialize(
        string $email,
        int $amountMinorUnits,
        string $currency,
        string $reference,
        array $metadata,
        ?string $callbackUrl,
    ): Response {
        $secret = config('paystack.secret_key');
        if ($secret === null || $secret === '') {
            throw new \RuntimeException('Paystack secret key is not configured.');
        }

        $payload = [
            'email' => $email,
            'amount' => $amountMinorUnits,
            'currency' => strtoupper($currency),
            'reference' => $reference,
            'metadata' => $metadata,
        ];

        if ($callbackUrl !== null && $callbackUrl !== '') {
            $payload['callback_url'] = $callbackUrl;
        }

        return Http::baseUrl((string) config('paystack.base_url'))
            ->withToken($secret)
            ->acceptJson()
            ->asJson()
            ->timeout(45)
            ->retry(2, 400)
            ->post('/transaction/initialize', $payload);
    }

    public function verify(string $reference): Response
    {
        $secret = config('paystack.secret_key');
        if ($secret === null || $secret === '') {
            throw new \RuntimeException('Paystack secret key is not configured.');
        }

        $reference = rawurlencode($reference);

        return Http::baseUrl((string) config('paystack.base_url'))
            ->withToken($secret)
            ->acceptJson()
            ->timeout(45)
            ->retry(2, 400)
            ->get("/transaction/verify/{$reference}");
    }
}
