<?php

namespace App\Services\Paystack;

use App\Enums\OrderPaymentStatus;
use App\Models\Order;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

final class PaystackPaymentInitializer
{
    public function __construct(
        private readonly PaystackClient $client,
    ) {}

    /**
     * Create a pending Payment and initialize Paystack hosted checkout.
     *
     * @param  Collection<int, Order>|array<int, Order>  $orders
     * @return array{
     *     payment: Payment,
     *     authorization_url: string,
     *     access_code: string|null,
     *     reference: string,
     *     public_key: string|null,
     *     amount_minor: int,
     *     currency: string
     * }
     */
    public function initialize(User $customer, Collection|array $orders, ?string $callbackUrl = null): array
    {
        $orders = Collection::wrap($orders)->values();

        if ($orders->isEmpty()) {
            throw ValidationException::withMessages([
                'orders' => ['At least one order is required to start payment.'],
            ]);
        }

        foreach ($orders as $order) {
            if ((int) $order->customer_id !== (int) $customer->id) {
                throw ValidationException::withMessages([
                    'orders' => ['One or more orders were not found on your account.'],
                ]);
            }

            $status = $order->payment_status instanceof OrderPaymentStatus
                ? $order->payment_status
                : OrderPaymentStatus::from((string) $order->payment_status);

            if ($status !== OrderPaymentStatus::Unpaid) {
                throw ValidationException::withMessages([
                    'orders' => ['All selected orders must be unpaid.'],
                ]);
            }
        }

        $currencies = $orders->pluck('currency')->unique();
        if ($currencies->count() > 1) {
            throw ValidationException::withMessages([
                'orders' => ['All orders in one payment must use the same currency.'],
            ]);
        }

        $currency = strtoupper((string) $currencies->first());
        $merchantCurrency = strtoupper((string) config('paystack.currency', 'GHS'));

        if ($currency !== $merchantCurrency) {
            throw ValidationException::withMessages([
                'orders' => ["Currency {$currency} is not supported. Use {$merchantCurrency} for Paystack payments."],
            ]);
        }

        $totalMajor = round($orders->sum(fn (Order $o) => (float) $o->total), 2);
        $amountMinor = PaystackMoney::toMinorUnits($totalMajor, $currency);
        $reference = $this->uniquePaymentReference();

        $payment = Payment::query()->create([
            'customer_id' => $customer->id,
            'reference' => $reference,
            'amount' => $amountMinor,
            'currency' => $currency,
            'status' => Payment::STATUS_PENDING,
            'metadata' => [
                'order_ids' => $orders->pluck('id')->values()->all(),
                'order_numbers' => $orders->pluck('order_number')->values()->all(),
            ],
        ]);

        $response = $this->client->initialize(
            (string) $customer->email,
            $amountMinor,
            $currency,
            $reference,
            [
                'customer_id' => $customer->id,
                'payment_id' => $payment->id,
            ],
            $callbackUrl ?: (string) config('paystack.callback_url'),
        );

        if (! $response->successful()) {
            $payment->update(['status' => Payment::STATUS_FAILED]);

            $message = $response->json('message') ?? 'Paystack initialize failed.';

            throw ValidationException::withMessages([
                'paystack' => [$message],
            ]);
        }

        $data = $response->json('data') ?? [];
        $authorizationUrl = $data['authorization_url'] ?? null;

        if (! is_string($authorizationUrl) || $authorizationUrl === '') {
            $payment->update(['status' => Payment::STATUS_FAILED]);

            throw ValidationException::withMessages([
                'paystack' => ['Paystack did not return a payment URL.'],
            ]);
        }

        $payment->update([
            'paystack_access_code' => $data['access_code'] ?? null,
            'paystack_reference' => $data['reference'] ?? $reference,
        ]);

        return [
            'payment' => $payment->fresh(),
            'authorization_url' => $authorizationUrl,
            'access_code' => $data['access_code'] ?? null,
            'reference' => $reference,
            'public_key' => config('paystack.public_key'),
            'amount_minor' => $amountMinor,
            'currency' => $currency,
        ];
    }

    private function uniquePaymentReference(): string
    {
        do {
            $reference = 'PAY-'.strtoupper(bin2hex(random_bytes(10)));
        } while (Payment::query()->where('reference', $reference)->exists());

        return $reference;
    }
}
