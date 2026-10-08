import 'package:dartvex/dartvex.dart';

/// Isolated Convex transport. It stays unused until a deployment and a verified
/// OIDC JWT are configured by the application.
class ConvexSyncGateway {
  ConvexSyncGateway._(this.deploymentUrl, this._client);

  factory ConvexSyncGateway.fromDeploymentUrl(String? value) {
    final url = value?.trim();
    if (url == null || url.isEmpty) return ConvexSyncGateway._(null, null);
    final uri = Uri.tryParse(url);
    final isLocal =
        uri != null &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1');
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'https' || (uri.scheme == 'http' && isLocal)) ||
        uri.path.isNotEmpty && uri.path != '/' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        value,
        'deploymentUrl',
        'URL de Convex no segura o inválida.',
      );
    }
    return ConvexSyncGateway._(
      uri.replace(path: '', query: null, fragment: null).toString(),
      ConvexClient(
        uri.toString(),
        config: const ConvexClientConfig(connectImmediately: false),
      ),
    );
  }

  factory ConvexSyncGateway.fromEnvironment() =>
      ConvexSyncGateway.fromDeploymentUrl(
        const String.fromEnvironment('BRUGES_CONVEX_URL'),
      );

  final String? deploymentUrl;
  final ConvexClient? _client;
  bool _hasIdentityToken = false;

  bool get isConfigured => _client != null;
  bool get hasIdentityToken => _hasIdentityToken;

  Future<void> setIdentityToken(String token) async {
    final client = _client;
    if (client == null) throw StateError('Convex no está configurado.');
    if (token.trim().isEmpty) throw ArgumentError.value(token, 'token');
    await client.setAuth(token);
    _hasIdentityToken = true;
  }

  void requireAuthenticated() {
    if (_client == null || !_hasIdentityToken) {
      throw StateError('Se requiere un despliegue y una sesión verificada.');
    }
  }

  ConvexSubscription subscribeOwnMovements() {
    requireAuthenticated();
    return _client!.subscribe('movements:listOwn');
  }

  Future<dynamic> createManualMovement(Map<String, dynamic> args) {
    requireAuthenticated();
    return _client!.mutate('movements:createManual', args);
  }

  void dispose() => _client?.dispose();
}
