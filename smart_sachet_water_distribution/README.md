# Smart Sachet Water Distribution

Flutter client for the Smart Sachet marketplace (customer · vendor · admin) against a Laravel Sanctum API.

## Features

- Role-based auth (login, register, **forgot/reset password**)
- Customer shop, cart (**badge**), checkout, Paystack, orders
- **Order status notifications** (local alerts + optional device-token API)
- **Live map tracking** while an order is out for delivery
- **Shareable PDF receipts**
- Vendor products, zones, order fulfillment, courier location publish
- Admin vendor approval, reports, ops map (order approval is vendor-only)
- Maps with **Google Directions** road routes (when API key is passed to Dart)
- Vendor **ratings / reviews** on listings and storefronts
- **Pagination** + offline **cache** for orders/cart snapshots

### Paystack checkout

Payments open in an **in-app WebView**. On success the app detects the return URL
(`smartsachet://paystack/callback` or a URL with `reference` / `trxref`) and
**auto-calls** `POST /customer/payments/paystack/verify`.

Pass `callback_url` from the app when initializing (backend should forward it to
Paystack). Deep link scheme: `smartsachet://paystack/callback`.

## Setup

```bash
flutter pub get
```

### API base URL

```bash
flutter run --dart-define=API_BASE_URL=https://your-api.com/api/v1/
```

Default (dev) is in `lib/core/config/api_config.dart`.

### Google Maps + Directions

1. Put the Maps SDK key in `android/local.properties`:

   ```
   GOOGLE_MAPS_API_KEY=your_key
   ```

2. Enable **Maps SDK for Android/iOS** and **Directions API** on that key.

3. Pass the same key to Dart so road routing / live track polylines work:

   ```bash
   flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key --dart-define=API_BASE_URL=...
   ```

### Vendor auto-approve

Vendors can schedule automatic approval of pending orders:

- **A)** One-time start/end date & time window  
- **B)** Weekly recurring days + daily hours (overnight ranges supported)  
- Master **Enable** switch and **Stop** to turn off immediately  

**Activation rule:** Enable alone does **not** approve orders. Auto-approve
only runs while Enable is on **and** the current time falls inside a valid
one-time window and/or weekly hours (either may match).

While the vendor app is open and the schedule is active, pending orders are
approved automatically. Expired one-time windows are cleared (or the feature
stopped if weekly isn’t configured). Settings sync to `PUT /vendor/profile`
when the backend supports the `auto_approve_*` fields; otherwise they still
work locally.

### Notifications

- **Customers:** local alerts when order status changes (while app is open).
- **Vendors:** local alerts when a **new customer order** appears (polls every ~25s while signed in).
- Backend should also send **FCM/SMS** for true push when the app is closed.
- Optional: `POST /customer/device-tokens` / `POST /vendor/device-tokens`.

### Password reset (backend)

```
POST /{role}/auth/forgot-password  { "email": "..." }
POST /{role}/auth/reset-password   { "email", "token", "password", "password_confirmation" }
```

### Live tracking (backend)

```
GET  /customer/orders/{order}/tracking
POST /vendor/orders/{order}/location  { "latitude", "longitude" }
```

Order payloads may also include `courier_latitude` / `courier_longitude`.

## Tests & CI

```bash
flutter test
flutter analyze
```

GitHub Actions: `.github/workflows/ci.yml` runs analyze + tests on push/PR.

## Project layout

- `lib/features/auth` — sessions, login/register/reset
- `lib/features/customer` — cart, orders, tracking, receipts
- `lib/features/vendor` — catalog, zones, fulfillment
- `lib/features/admin` — approvals, reports, map
- `lib/features/maps` — clustering, zones, Directions routes
- `lib/core` — Dio, cache, pagination, notifications
