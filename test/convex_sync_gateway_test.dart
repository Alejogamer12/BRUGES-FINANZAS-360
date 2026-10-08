import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/data/remote/convex_sync_gateway.dart';

void main() {
  test('keeps cloud sync unavailable when no deployment is configured', () {
    final gateway = ConvexSyncGateway.fromDeploymentUrl(null);

    expect(gateway.isConfigured, isFalse);
    expect(() => gateway.requireAuthenticated(), throwsStateError);
    gateway.dispose();
  });

  test('accepts only secure deployment URLs outside localhost', () {
    expect(
      () => ConvexSyncGateway.fromDeploymentUrl('http://finance.example'),
      throwsArgumentError,
    );
    final gateway = ConvexSyncGateway.fromDeploymentUrl(
      'https://bruges-finanzas.convex.cloud',
    );
    expect(gateway.isConfigured, isTrue);
    gateway.dispose();
  });
}
