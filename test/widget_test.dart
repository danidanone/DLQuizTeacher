import 'package:flutter_test/flutter_test.dart';
import 'package:mini_kahoot_teacher/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Esto es una prueba básica para asegurarse de que la app no crashea al iniciar.
    // Ten en cuenta que para pruebas más complejas con Firebase, necesitarás 
    // simular los servicios de Firebase.
    await tester.pumpWidget(const MyApp());

    // Verifica que el título de la AppBar se muestra.
    expect(find.text('Profesor - Mini Kahoot'), findsOneWidget);
  });
}
