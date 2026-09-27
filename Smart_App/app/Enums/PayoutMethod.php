<?php

namespace App\Enums;

enum PayoutMethod: string
{
    case Bank = 'bank';
    case MobileMoney = 'mobile_money';
}
