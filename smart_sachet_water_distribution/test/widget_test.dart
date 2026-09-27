import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/app.dart';
import 'package:smart_sachet_water_distribution/core/network/dio_client.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/auth_api.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/auth_repository.dart';
import 'package:smart_sachet_water_distribution/features/auth/data/token_storage.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/cart_controller.dart';

void main() {
  testWidgets('app builds and shows auth flow', (WidgetTester tester) async {
    final dio = createDio();
    final auth = AuthController(
      AuthRepository(
        api: AuthApi(dio),
        storage: TokenStorage(),
      ),
    )..bootstrap();
    final cart = CartController(dio, auth);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Dio>.value(value: dio),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<CartController>.value(value: cart),
        ],
        child: const SmartSachetApp(),
      ),
    );

    await tester.pump();
    expect(find.byType(SmartSachetApp), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.textContaining('Water Delivery'), findsWidgets);
  });
}
