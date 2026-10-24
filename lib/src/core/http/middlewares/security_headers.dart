import '../context.dart';
import '../middleware.dart';

/// Standard security headers (Helmet equivalent) middleware for Endvein.
EndveinMiddleware securityHeaders({
  String xssProtection = '1; mode=block',
  String frameOptions = 'SAMEORIGIN',
  String contentTypeOptions = 'nosniff',
  String referrerPolicy = 'no-referrer',
  String? contentSecurityPolicy,
}) {
  return (EndveinContext ctx, NextFunction next) async {
    ctx.setHeader('X-XSS-Protection', xssProtection);
    ctx.setHeader('X-Frame-Options', frameOptions);
    ctx.setHeader('X-Content-Type-Options', contentTypeOptions);
    ctx.setHeader('Referrer-Policy', referrerPolicy);
    if (contentSecurityPolicy != null) {
      ctx.setHeader('Content-Security-Policy', contentSecurityPolicy);
    }

    return await next();
  };
}
