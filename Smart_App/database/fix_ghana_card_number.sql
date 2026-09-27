-- Fix: add ghana_card_number to vendor_profiles
-- Run this in phpMyAdmin on the `marketplace` database, then retry vendor registration.

ALTER TABLE vendor_profiles
  ADD COLUMN ghana_card_number VARCHAR(20) NULL UNIQUE AFTER phone;
