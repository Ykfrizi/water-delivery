Sachet and Bottled Water Distribution System
A cross-platform, multi-vendor mobile platform that lets registered sachet and bottle water companies in Ho Municipality list products, receive orders, and coordinate delivery, while customers discover nearby vendors through their device's own location services and pay securely through Paystack.
•	Backend: PHP (Laravel), MySQL
•	Frontend: Flutter (Android/iOS)
•	Payments: Paystack
•	Location: Mobile device location services + Google Maps Platform (admin dashboard)

Project Structure
Folder	Description
smart_App	Backend database/API project (Laravel)
smart_sachet_water_distribution	Frontend mobile app project (Flutter)


1. Backend Setup (Laravel + MySQL)
Prerequisites
•	XAMPP installed
•	PHP and Composer installed
•	Your computer and your phone/emulator connected to the same Wi-Fi network
Steps
1.	Start XAMPP. Open the XAMPP Control Panel and start both Apache and MySQL.
2.	Find your computer's local IP address. This is the address your phone will use to reach the backend, since localhost only works on the same machine.
•	Windows: open Command Prompt and run ipconfig — look for IPv4 Address (e.g. 192.168.1.15).
•	macOS/Linux: open Terminal and run ifconfig (or ip addr) — look for the address under your active Wi-Fi interface.
3.	Open a terminal in the database project folder (smart_App) and start the Laravel development server, binding it to your machine's IP address so it's reachable from other devices on the network:
php artisan serve --host=<your-ip-address> --port=8000
Example:
php artisan serve --host=192.168.1.15 --port=8000
Keep this terminal window open while you use the app — the server stops when you close it.

2. Frontend Setup (Flutter)
1.	Open the app project (smart_sachet_water_distribution) in Android Studio (or your preferred editor).
2.	Point the app at your backend. Open the API configuration file (api_config.dart) and set API_BASE_URL to the same IP address and port you used in step 1, followed by /api/v1:
defaultValue: 'http://<your-ip-address>:8000/api/v1',
Example:
defaultValue: 'http://192.168.1.15:8000/api/v1',
This value must always match the --host and --port you used when starting php artisan serve in step 1, or the app won't be able to reach the backend.
3.	Install dependencies:
flutter pub get
4.	Run the app on either a virtual device (emulator) or a physical device connected via USB or wireless debugging (see below).

3. Preparing a Physical Device (Android)
If you're testing on a real Android phone instead of an emulator, you first need to enable Developer Options and turn on debugging:
1.	Go to Settings → About Phone → Version Info.
2.	Find Build Number and tap it 5 times in a row. You'll see a message confirming that Developer Options is now enabled.
3.	Go back to Settings → System → Developer Options.
4.	Turn on either:
•	USB Debugging — then connect your phone to your computer with a USB cable, or
•	Wireless Debugging — then pair your phone and computer over the same Wi-Fi network.
5.	Confirm your device appears in Android Studio's device dropdown, then run the app as normal.

4. Demo Accounts
The system ships with four seeded accounts, one for each role, so you can explore the app immediately without registering a new user:
Role	Email	Password
Admin	admin@example.com	password
Customer	customer@example.com	password
Vendor — Amenuveve Enterprise	v@gmail.com	password
Vendor — YK	yk@gmail.com	password

Log in as Admin to review and approve vendors and monitor activity on the map dashboard; as Customer to browse nearby vendors, order sachet or bottle water, and pay through Paystack or as either Vendor account to manage products, delivery zones, and incoming orders.

Quick Start Checklist
•	☐ XAMPP Apache and MySQL are running
•	☐ php artisan serve --host=<ip> --port=8000 is running in a terminal inside smart_App
•	☐ API_BASE_URL in smart_sachet_water_distribution matches that same IP and port
•	☐ flutter pub get has been run
•	☐ Developer Options + USB/Wireless Debugging enabled (physical device only)
•	☐ App launched and logged in with one of the demo accounts above

