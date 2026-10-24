import 'package:endvein/endvein.dart';

void main() async {
  final cluster = EndveinCluster(
    host: '0.0.0.0',
    port: 8080,
    engineMode: EngineMode.rawSocket,
    // Worker Lifecycle Hooks: Ideal for initializing Per-Isolate DB Connection Pools
    onWorkerInit: (workerId) {
      // ignore: avoid_print
      print('📦 [Worker #$workerId] Initialized isolate resources.');
    },
    onWorkerShutdown: (workerId) {
      // ignore: avoid_print
      print('🛑 [Worker #$workerId] Closed isolate resources.');
    },
    routerFactory: () {
      final router = EndveinRouter();

      // 1. Built-in Security Middlewares
      router.use(cors());
      router.use(securityHeaders());

      // 2. Global Request Timer Middleware
      router.use((ctx, next) async {
        final stopwatch = Stopwatch()..start();
        final response = await next();
        stopwatch.stop();
        ctx.setHeader('X-Response-Time', '${stopwatch.elapsedMicroseconds}us');
        return response;
      });

      // 3. Root Endpoint
      router.get(
        '/',
        (ctx) => {
          'framework': 'Endvein',
          'status': 'hardened_and_blazing_fast',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      router.get('/health', (ctx) => 'OK');

      // 4. API v1 Route Grouping
      router.group('/api/v1', (v1) {
        // Dynamic Route with Type-Safe param parsing
        v1.get('/users/:id', (ctx) {
          final userId = ctx.paramInt('id');
          final role = ctx.queryString('role', defaultValue: 'Engineer');
          return {
            'id': userId,
            'name': 'User #$userId',
            'role': role,
          };
        });

        // Protected Sub-group with Scoped Middleware
        v1.group('/admin', (admin) {
          admin.use((ctx, next) async {
            final auth = ctx.getHeader('authorization');
            if (auth != 'Bearer admin-token') {
              return EndveinResponse.json(
                {'error': 'Unauthorized', 'hint': 'Pass Authorization: Bearer admin-token'},
                statusCode: 401,
              );
            }
            return next();
          });

          admin.get('/metrics', (ctx) => {
            'active_workers': 'all_cores',
            'status': 'healthy',
            'cluster': 'supervised',
          });
        });
      });

      return router;
    },
  );

  await cluster.run();
}
