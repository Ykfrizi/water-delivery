<?php

namespace App\Notifications;

use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class PasswordResetCodeNotification extends Notification
{
    public function __construct(
        public readonly string $code,
    ) {}

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $minutes = 15;
        $name = is_string($notifiable->name ?? null) && $notifiable->name !== ''
            ? $notifiable->name
            : 'there';

        return (new MailMessage)
            ->subject('Your Water Delivery password reset code')
            ->greeting('Hello '.$name.',')
            ->line('Use this 6-digit code in the Water Delivery app to set a new password:')
            ->line($this->code)
            ->line("This code expires in {$minutes} minutes.")
            ->line('If you did not ask to reset your password, you can ignore this email.');
    }
}
