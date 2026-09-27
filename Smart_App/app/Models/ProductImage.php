<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

class ProductImage extends Model
{
    protected $fillable = [
        'product_id',
        'path',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'sort_order' => 'integer',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function getUrlAttribute(): string
    {
        $relative = 'storage/'.ltrim(str_replace('\\', '/', (string) $this->path), '/');

        // Prefer the host the client actually used so phones on LAN do not get
        // http://localhost/storage/... from APP_URL.
        $request = request();
        if ($request !== null) {
            return $request->getSchemeAndHttpHost().'/'.$relative;
        }

        return Storage::disk('public')->url($this->path);
    }
}
