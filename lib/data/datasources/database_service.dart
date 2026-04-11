// Exportação condicional:
// - Plataformas nativas (Windows/Linux/macOS): usa Firebird via fbdb
// - Web: usa stub sem dependências nativas
export 'database_service_io.dart'
    if (dart.library.js_interop) 'database_service_web.dart';
