/// Zero-Cost Type-Safe HTTP Abstractions powered by Dart 3.3+ Extension Types.
/// These types provide compile-time type safety with 0 bytes runtime allocation overhead.
library endvein.headers;

/// Type-safe HTTP Header Name with zero runtime allocation overhead.
extension type const HeaderName(String name) {
  static const contentType = HeaderName('content-type');
  static const authorization = HeaderName('authorization');
  static const contentLength = HeaderName('content-length');
  static const accept = HeaderName('accept');
  static const acceptEncoding = HeaderName('accept-encoding');
  static const userAgent = HeaderName('user-agent');
  static const host = HeaderName('host');
  static const origin = HeaderName('origin');
  static const connection = HeaderName('connection');
  static const server = HeaderName('server');
  static const cacheControl = HeaderName('cache-control');
  static const etag = HeaderName('etag');
  static const location = HeaderName('location');
  static const cookie = HeaderName('cookie');
  static const setCookie = HeaderName('set-cookie');
  static const xRequestId = HeaderName('x-request-id');
  static const xForwardedFor = HeaderName('x-forwarded-for');
  static const xRealIp = HeaderName('x-real-ip');
  static const xRateLimitLimit = HeaderName('x-ratelimit-limit');
  static const xRateLimitRemaining = HeaderName('x-ratelimit-remaining');
  static const xRateLimitReset = HeaderName('x-ratelimit-reset');
  static const retryAfter = HeaderName('retry-after');

  /// String value of the header name.
  String get value => name;
}

/// Type-safe MIME / Content-Type representation with zero runtime allocation overhead.
extension type const MediaType(String value) {
  static const json = MediaType('application/json; charset=utf-8');
  static const textPlain = MediaType('text/plain; charset=utf-8');
  static const html = MediaType('text/html; charset=utf-8');
  static const octetStream = MediaType('application/octet-stream');
  static const formData = MediaType('multipart/form-data');
  static const formUrlEncoded = MediaType('application/x-www-form-urlencoded');
  static const eventStream = MediaType('text/event-stream; charset=utf-8');
  static const css = MediaType('text/css; charset=utf-8');
  static const javascript = MediaType('application/javascript; charset=utf-8');

  /// Check if this media type is JSON.
  bool get isJson => value.contains('application/json');

  /// Check if this media type is plain text.
  bool get isText => value.contains('text/plain');

  /// Check if this media type is HTML.
  bool get isHtml => value.contains('text/html');

  /// Check if this media type is Server-Sent Events stream.
  bool get isEventStream => value.contains('text/event-stream');
}

/// Type-safe HTTP Status Code with zero runtime allocation overhead.
extension type const StatusCode(int code) {
  static const ok = StatusCode(200);
  static const created = StatusCode(201);
  static const accepted = StatusCode(202);
  static const noContent = StatusCode(204);
  static const movedPermanently = StatusCode(301);
  static const found = StatusCode(302);
  static const notModified = StatusCode(304);
  static const badRequest = StatusCode(400);
  static const unauthorized = StatusCode(401);
  static const forbidden = StatusCode(403);
  static const notFound = StatusCode(404);
  static const methodNotAllowed = StatusCode(405);
  static const conflict = StatusCode(409);
  static const payloadTooLarge = StatusCode(413);
  static const uriTooLong = StatusCode(414);
  static const unprocessableEntity = StatusCode(422);
  static const tooManyRequests = StatusCode(429);
  static const requestHeaderFieldsTooLarge = StatusCode(431);
  static const internalServerError = StatusCode(500);
  static const notImplemented = StatusCode(501);
  static const badGateway = StatusCode(502);
  static const serviceUnavailable = StatusCode(503);

  /// Returns true if status code is in 2xx range.
  bool get isSuccess => code >= 200 && code < 300;

  /// Returns true if status code is in 3xx range.
  bool get isRedirection => code >= 300 && code < 400;

  /// Returns true if status code is in 4xx range.
  bool get isClientError => code >= 400 && code < 500;

  /// Returns true if status code is in 5xx range.
  bool get isServerError => code >= 500 && code < 600;
}
