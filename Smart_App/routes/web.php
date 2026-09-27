<?php

use App\Http\Controllers\DeliverySharePageController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/d/{token}', [DeliverySharePageController::class, 'show'])
    ->where('token', '[a-f0-9]{64}')
    ->name('delivery.share');

Route::get('/payment/callback', function () {
    $reference = request()->query('reference') ?? request()->query('trxref');

    return response()->view('payment.callback', [
        'reference' => $reference,
    ]);
})->name('payment.callback');
