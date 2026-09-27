<?php

namespace App\Services\Paystack;

use App\Enums\OrderPaymentStatus;
use App\Models\Order;
use App\Models\Payment;
use App\Notifications\CustomerPurchasedNotification;
use App\Notifications\OrderPaidNotification;
use App\Notifications\PaymentFailedNotification;
use App\Services\OrderAutoApprovalService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

final class PaystackPaymentProcessor
{
    public function __construct(
        private readonly PaystackClient $client,
    ) {}

    /**
     * Confirms payment from Paystack verify API or webhook (idempotent).
     *
     * @param  array<string, mixed>  $paystackData  `data` object from verify response or webhook payload
     */
    public function confirmPayment(Payment $payment, array $paystackData): bool
    {
        if ($payment->status === Payment::STATUS_SUCCESS) {
            return true;
        }

        $reference = $paystackData['reference'] ?? null;
        $status = $paystackData['status'] ?? null;
        $paidAt = $paystackData['paid_at'] ?? null;

        if ($status !== 'success') {
            if ($payment->status !== Payment::STATUS_FAILED) {
                $payment->update(['status' => Payment::STATUS_FAILED]);
                $customer = $payment->customer;
                if ($customer !== null) {
                    $customer->notify(new PaymentFailedNotification($payment->fresh()));
                }
            }

            return false;
        }

        $amountMinor = (int) ($paystackData['amount'] ?? 0);
        if ($amountMinor !== (int) $payment->amount) {
            Log::warning('Paystack amount mismatch', [
                'payment_id' => $payment->id,
                'expected_minor' => $payment->amount,
                'got_minor' => $amountMinor,
            ]);

            return false;
        }

        $currency = strtoupper((string) ($paystackData['currency'] ?? ''));
        if ($currency !== strtoupper($payment->currency)) {
            Log::warning('Paystack currency mismatch', [
                'payment_id' => $payment->id,
                'expected' => $payment->currency,
                'got' => $currency,
            ]);

            return false;
        }

        $confirmed = DB::transaction(function () use ($payment, $reference, $paidAt): bool {
            $payment->refresh();

            if ($payment->status === Payment::STATUS_SUCCESS) {
                return false;
            }

            $parsedPaidAt = $this->parsePaystackPaidAt($paidAt);

            $payment->update([
                'status' => Payment::STATUS_SUCCESS,
                'paystack_reference' => $reference ?? $payment->paystack_reference,
                'paid_at' => $parsedPaidAt,
            ]);

            $orderIds = $payment->metadata['order_ids'] ?? [];
            if (! is_array($orderIds) || $orderIds === []) {
                return false;
            }

            Order::query()
                ->whereIn('id', $orderIds)
                ->where('customer_id', $payment->customer_id)
                ->where('payment_status', OrderPaymentStatus::Unpaid->value)
                ->update([
                    'payment_status' => OrderPaymentStatus::Paid->value,
                    'paid_at' => $parsedPaidAt,
                ]);

            return true;
        });

        if ($confirmed) {
            $this->notifyPaid($payment->fresh());
            $this->autoApprovePaidOrders($payment->fresh());
        }

        return $payment->fresh()->status === Payment::STATUS_SUCCESS;
    }

    private function autoApprovePaidOrders(Payment $payment): void
    {
        $orderIds = $payment->metadata['order_ids'] ?? [];
        if (! is_array($orderIds) || $orderIds === []) {
            return;
        }

        $orders = Order::query()
            ->with(['customer', 'vendorProfile'])
            ->whereIn('id', $orderIds)
            ->get();

        foreach ($orders as $order) {
            OrderAutoApprovalService::maybeAutoConfirm($order);
        }
    }

    private function notifyPaid(Payment $payment): void
    {
        $orderIds = $payment->metadata['order_ids'] ?? [];
        if (! is_array($orderIds) || $orderIds === []) {
            return;
        }

        $orders = Order::query()
            ->with(['customer', 'vendorProfile.user', 'orderItems'])
            ->whereIn('id', $orderIds)
            ->get();

        $customer = $orders->first()?->customer ?? $payment->customer;
        if ($customer !== null) {
            foreach ($orders as $order) {
                $customer->notify(new OrderPaidNotification($order, 'customer'));
            }
        }

        foreach ($orders as $order) {
            $vendorUser = $order->vendorProfile?->user;
            if ($vendorUser !== null) {
                $vendorUser->notify(new CustomerPurchasedNotification($order));
            }
        }
    }

    private function parsePaystackPaidAt(mixed $paidAt): \Illuminate\Support\Carbon
    {
        if ($paidAt === null) {
            return now();
        }

        if (is_numeric($paidAt)) {
            return \Illuminate\Support\Carbon::createFromTimestamp((int) $paidAt);
        }

        return \Illuminate\Support\Carbon::parse((string) $paidAt);
    }
}
