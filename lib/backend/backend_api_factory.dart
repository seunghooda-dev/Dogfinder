import "api_contract.dart";
import "backend_config.dart";
import "rest_backend_api.dart";

BackendApi? createBackendApiFromEnvironment() {
  final config = BackendConfig.fromEnvironment();
  if (config == null) return null;
  return RestBackendApi(config: config);
}
