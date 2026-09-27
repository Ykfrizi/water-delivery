<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\NotificationResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Notifications\DatabaseNotification;

class NotificationController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $perPage = min(max((int) $request->input('per_page', 20), 1), 100);
        $user = $request->user();

        $query = $user->notifications()->latest();

        if ($request->boolean('unread_only')) {
            $query->whereNull('read_at');
        }

        return NotificationResource::collection($query->paginate($perPage));
    }

    public function unreadCount(Request $request): JsonResponse
    {
        return response()->json([
            'unread_count' => $request->user()->unreadNotifications()->count(),
        ]);
    }

    public function markAsRead(Request $request, string $notification): NotificationResource
    {
        $item = $this->findOwnedNotification($request, $notification);

        if ($item->read_at === null) {
            $item->markAsRead();
        }

        return new NotificationResource($item->fresh());
    }

    public function markAllAsRead(Request $request): JsonResponse
    {
        $request->user()->unreadNotifications->markAsRead();

        return response()->json([
            'message' => 'All notifications marked as read.',
            'unread_count' => 0,
        ]);
    }

    public function destroy(Request $request, string $notification): JsonResponse
    {
        $item = $this->findOwnedNotification($request, $notification);
        $item->delete();

        return response()->json(['message' => 'Notification deleted.']);
    }

    private function findOwnedNotification(Request $request, string $notificationId): DatabaseNotification
    {
        $item = $request->user()
            ->notifications()
            ->where('id', $notificationId)
            ->first();

        if ($item === null) {
            abort(404);
        }

        return $item;
    }
}
