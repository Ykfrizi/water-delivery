<?php

namespace App\Http\Controllers\Api\V1\Payments;

use App\Http\Controllers\Controller;
use App\Models\Payment;
use App\Services\Paystack\PaystackPaymentProcessor;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;

class PaystackWebhookController extends Controller
{
    public function __construct(
        private readonly PaystackPaymentProcessor $processor,
    ) {}

    public function handle(Request $request): Response
    {
        $secret = config('paystack.secret_key');
        if ($secret === null || $secret === '') {
            Log::warning('Paystack webhook received but secret key is not configured.');

            return response('Paystack not configured', 500);
        }

        $payload = $request->getContent();
        $signature = $request->header('x-paystack-signature');

        $computed = hash_hmac('sha512', $payload, $secret);

        if ($signature === null || ! hash_equals($computed, $signature)) {
            return response('Invalid signature', 401);
        }

        $event = $request->json('event');
        $data = $request->json('data');

        if ($event !== 'charge.success' || ! is_array($data)) {
            return response('OK', 200);
        }

        $reference = $data['reference'] ?? null;
        if ($reference === null || $reference === '') {
            return response('OK', 200);
        }

        $payment = Payment::query()->where('reference', $reference)->first();
        if ($payment === null) {
            Log::info('Paystack webhook: unknown reference', ['reference' => $reference]);

            return response('OK', 200);
        }

        $this->processor->confirmPayment($payment->fresh(), $data);

        return response('OK', 200);
    }
}
