// build/web を配信するだけの簡易静的サーバ（dart:io のみ・依存なし）。
// プレビュー用。`dart run tool/serve_web.dart` で 127.0.0.1:8080 に配信。
import 'dart:io';

const _contentTypes = {
  'html': 'text/html; charset=utf-8',
  'js': 'application/javascript',
  'mjs': 'application/javascript',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'css': 'text/css',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'map': 'application/json',
};

Future<void> main() async {
  final root = Directory('build/web');
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Serving ${root.path} on http://127.0.0.1:$port');

  await for (final req in server) {
    try {
      var path = req.uri.path;
      if (path == '/' || path.isEmpty) path = '/index.html';
      var file = File('${root.path}$path');
      if (!await file.exists()) {
        file = File('${root.path}/index.html'); // SPA フォールバック
      }
      final ext = file.path.contains('.') ? file.path.split('.').last : 'html';
      req.response.headers.set(
        HttpHeaders.contentTypeHeader,
        _contentTypes[ext] ?? 'application/octet-stream',
      );
      await req.response.addStream(file.openRead());
    } catch (_) {
      req.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await req.response.close();
    }
  }
}
