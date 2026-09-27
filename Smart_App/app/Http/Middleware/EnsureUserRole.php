<?php

namespace App\Http\Middleware;

use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureUserRole
{
    public function handle(Request $request, Closure $next, string $role): Response
    {
        $user = $request->user();

        if (! $user instanceof User || $user->role->value !== $role) {
            abort(Response::HTTP_FORBIDDEN, 'This action is unauthorized.');
        }

        return $next($request);
    }
}
