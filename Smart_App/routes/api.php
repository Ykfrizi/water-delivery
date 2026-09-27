<?php

use App\Http\Controllers\Api\V1\Admin\AdminMapController;
use App\Http\Controllers\Api\V1\Admin\AdminOrderController;
use App\Http\Controllers\Api\V1\Admin\AdminPaymentController;
use App\Http\Controllers\Api\V1\Admin\AdminReportController;
use App\Http\Controllers\Api\V1\Admin\AdminVendorController;
use App\Http\Controllers\Api\V1\Admin\AdminVoucherController;
use App\Http\Controllers\Api\V1\Admin\AdminWithdrawalController;
use App\Http\Controllers\Api\V1\Admin\AuthController as AdminAuthController;
use App\Http\Controllers\Api\V1\Customer\AuthController as CustomerAuthController;
use App\Http\Controllers\Api\V1\Customer\CustomerCartController;
use App\Http\Controllers\Api\V1\Customer\CustomerCheckoutController;
use App\Http\Controllers\Api\V1\Customer\CustomerOrderController;
use App\Http\Controllers\Api\V1\Customer\CustomerVoucherController;
use App\Http\Controllers\Api\V1\Customer\PaystackPaymentController;
use App\Http\Controllers\Api\V1\Customer\VendorReviewController as CustomerVendorReviewController;
use App\Http\Controllers\Api\V1\LiveLocationController;
use App\Http\Controllers\Api\V1\NotificationController;
use App\Http\Controllers\Api\V1\Payments\PaystackWebhookController;
use App\Http\Controllers\Api\V1\Marketplace\VendorDirectoryController;
use App\Http\Controllers\Api\V1\Vendor\AuthController as VendorAuthController;
use App\Http\Controllers\Api\V1\Vendor\VendorOrderController;
use App\Http\Controllers\Api\V1\Vendor\VendorDeliveryZoneController;
use App\Http\Controllers\Api\V1\Vendor\VendorProductController;
use App\Http\Controllers\Api\V1\Vendor\VendorProfileController;
use App\Http\Controllers\Api\V1\Vendor\VendorWithdrawalController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::post('payments/paystack/webhook', [PaystackWebhookController::class, 'handle'])
        ->middleware('throttle:120,1');

    Route::get('/', function () {
        return response()->json([
            'name' => 'Smart_App API',
            'version' => 1,
            'docs' => 'Use paths under /api/v1 (e.g. /api/v1/marketplace/vendors). This root has no list of all routes.',
        ]);
    });

    Route::prefix('marketplace')->group(function () {
        Route::get('vendors', [VendorDirectoryController::class, 'index']);
        Route::get('vendors/{vendor}', [VendorDirectoryController::class, 'show']);
        Route::get('vendors/{vendor}/products', [VendorDirectoryController::class, 'products']);
        Route::get('vendors/{vendor}/reviews', [VendorDirectoryController::class, 'reviews']);
    });

    Route::prefix('customer')->group(function () {
        Route::post('auth/register', [CustomerAuthController::class, 'register']);
        Route::post('auth/login', [CustomerAuthController::class, 'login']);
        Route::post('auth/forgot-password', [CustomerAuthController::class, 'forgotPassword'])
            ->middleware('throttle:5,1');
        Route::post('auth/reset-password', [CustomerAuthController::class, 'resetPassword'])
            ->middleware('throttle:10,1');

        Route::middleware(['auth:sanctum', 'role:customer'])->group(function () {
            Route::get('me', [CustomerAuthController::class, 'me']);
            Route::match(['put', 'patch'], 'me', [CustomerAuthController::class, 'update']);
            Route::post('auth/logout', [CustomerAuthController::class, 'logout']);
            Route::post('vendors/{vendor}/reviews', [CustomerVendorReviewController::class, 'store']);

            Route::get('notifications', [NotificationController::class, 'index']);
            Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
            Route::post('notifications/read-all', [NotificationController::class, 'markAllAsRead']);
            Route::post('notifications/{notification}/read', [NotificationController::class, 'markAsRead']);
            Route::delete('notifications/{notification}', [NotificationController::class, 'destroy']);

            Route::post('location', [LiveLocationController::class, 'store']);

            Route::get('cart', [CustomerCartController::class, 'show']);
            Route::post('cart/items', [CustomerCartController::class, 'addItem']);
            Route::patch('cart/items/{cart_item}', [CustomerCartController::class, 'updateItem']);
            Route::delete('cart/items/{cart_item}', [CustomerCartController::class, 'removeItem']);
            Route::delete('cart', [CustomerCartController::class, 'clear']);

            Route::post('checkout', [CustomerCheckoutController::class, 'store']);
            Route::get('vouchers/preview', [CustomerVoucherController::class, 'show']);

            Route::post('payments/paystack/initialize', [PaystackPaymentController::class, 'initialize']);
            Route::match(['get', 'post'], 'payments/paystack/verify', [PaystackPaymentController::class, 'verify']);

            Route::get('orders', [CustomerOrderController::class, 'index']);
            Route::get('orders/{order}', [CustomerOrderController::class, 'show']);
            Route::patch('orders/{order}', [CustomerOrderController::class, 'update']);
        });
    });

    Route::prefix('vendor')->group(function () {
        Route::post('auth/register', [VendorAuthController::class, 'register']);
        Route::post('auth/login', [VendorAuthController::class, 'login']);
        Route::post('auth/complete-profile', [VendorAuthController::class, 'completeProfile']);
        Route::post('auth/forgot-password', [VendorAuthController::class, 'forgotPassword'])
            ->middleware('throttle:5,1');
        Route::post('auth/reset-password', [VendorAuthController::class, 'resetPassword'])
            ->middleware('throttle:10,1');

        Route::middleware(['auth:sanctum', 'role:vendor'])->group(function () {
            Route::get('me', [VendorAuthController::class, 'me']);
            Route::post('auth/logout', [VendorAuthController::class, 'logout']);
            Route::get('profile', [VendorProfileController::class, 'show']);
            Route::get('reviews', [VendorProfileController::class, 'reviews']);

            Route::get('notifications', [NotificationController::class, 'index']);
            Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
            Route::post('notifications/read-all', [NotificationController::class, 'markAllAsRead']);
            Route::post('notifications/{notification}/read', [NotificationController::class, 'markAsRead']);
            Route::delete('notifications/{notification}', [NotificationController::class, 'destroy']);

            Route::post('location', [LiveLocationController::class, 'store']);

            Route::middleware('vendor.approved')->group(function () {
                Route::put('profile', [VendorProfileController::class, 'update']);
                Route::post('profile/auto-approve/stop', [VendorProfileController::class, 'stopAutoApprove']);
                Route::apiResource('products', VendorProductController::class);
                Route::apiResource('delivery-zones', VendorDeliveryZoneController::class);

                Route::get('orders', [VendorOrderController::class, 'index']);
                Route::get('orders/{order}', [VendorOrderController::class, 'show']);
                Route::patch('orders/{order}', [VendorOrderController::class, 'update']);
                Route::post('orders/{order}/approve', [VendorOrderController::class, 'approve']);
                Route::post('orders/{order}/reject', [VendorOrderController::class, 'reject']);
                Route::post('orders/{order}/location', [VendorOrderController::class, 'updateLocation']);
                Route::post('orders/{order}/delivery-link', [VendorOrderController::class, 'createDeliveryLink'])
                    ->middleware('throttle:10,1');

                Route::get('wallet', [VendorWithdrawalController::class, 'wallet']);
                Route::get('withdrawals', [VendorWithdrawalController::class, 'index']);
                Route::post('withdrawals', [VendorWithdrawalController::class, 'store']);
            });
        });
    });

    Route::prefix('admin')->group(function () {
        Route::post('auth/login', [AdminAuthController::class, 'login']);
        Route::post('auth/forgot-password', [AdminAuthController::class, 'forgotPassword'])
            ->middleware('throttle:5,1');
        Route::post('auth/reset-password', [AdminAuthController::class, 'resetPassword'])
            ->middleware('throttle:10,1');

        Route::middleware(['auth:sanctum', 'role:admin'])->group(function () {
            Route::get('me', [AdminAuthController::class, 'me']);
            Route::post('auth/logout', [AdminAuthController::class, 'logout']);

            Route::get('notifications', [NotificationController::class, 'index']);
            Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
            Route::post('notifications/read-all', [NotificationController::class, 'markAllAsRead']);
            Route::post('notifications/{notification}/read', [NotificationController::class, 'markAsRead']);
            Route::delete('notifications/{notification}', [NotificationController::class, 'destroy']);

            Route::get('map', [AdminMapController::class, 'show']);

            Route::get('orders', [AdminOrderController::class, 'index']);
            Route::get('orders/{order}', [AdminOrderController::class, 'show']);
            Route::patch('orders/{order}', [AdminOrderController::class, 'update']);

            Route::get('vendors', [AdminVendorController::class, 'index']);
            Route::get('vendors/{vendor}', [AdminVendorController::class, 'show']);
            Route::match(['put', 'patch'], 'vendors/{vendor}', [AdminVendorController::class, 'update']);

            Route::get('reports', [AdminReportController::class, 'show']);

            Route::get('payments', [AdminPaymentController::class, 'index']);
            Route::get('withdrawals', [AdminWithdrawalController::class, 'index']);
            Route::post('withdrawals/{withdrawal}/complete', [AdminWithdrawalController::class, 'complete']);
            Route::post('withdrawals/{withdrawal}/reject', [AdminWithdrawalController::class, 'reject']);

            Route::get('vouchers', [AdminVoucherController::class, 'index']);
            Route::post('vouchers', [AdminVoucherController::class, 'store']);
            Route::match(['put', 'patch'], 'vouchers/{voucher}', [AdminVoucherController::class, 'update']);
            Route::delete('vouchers/{voucher}', [AdminVoucherController::class, 'destroy']);
        });
    });
});
