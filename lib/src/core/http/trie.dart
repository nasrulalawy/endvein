import 'http_method.dart';
import 'router.dart';

enum TrieNodeType {
  static,
  param,
  catchAll,
}

/// Result of matching a path against the Radix Tree.
class TrieSearchResult {
  final RouteTarget target;
  final Map<String, String> params;

  const TrieSearchResult(this.target, this.params);
}

/// A node within the Endvein Radix Tree Router.
class TrieNode {
  final TrieNodeType type;
  final String segment;
  final String? paramName;
  final Map<String, TrieNode> staticChildren = {};
  TrieNode? paramChild;
  TrieNode? catchAllChild;
  RouteTarget? target;

  TrieNode({
    this.type = TrieNodeType.static,
    this.segment = '',
    this.paramName,
  });

  /// Insert a route into the Radix Tree.
  void insert(List<String> segments, int index, RouteTarget target) {
    if (index == segments.length) {
      this.target = target;
      return;
    }

    final seg = segments[index];

    if (seg.startsWith('*')) {
      // Wildcard / catch-all route (e.g. *filepath)
      final pName = seg.length > 1 ? seg.substring(1) : 'wildcard';
      catchAllChild ??= TrieNode(
        type: TrieNodeType.catchAll,
        segment: seg,
        paramName: pName,
      );
      catchAllChild!.target = target;
      return;
    } else if (seg.startsWith(':')) {
      // Parameterized route (e.g. :id)
      final pName = seg.substring(1);
      paramChild ??= TrieNode(
        type: TrieNodeType.param,
        segment: seg,
        paramName: pName,
      );
      paramChild!.insert(segments, index + 1, target);
    } else {
      // Static route segment
      final child = staticChildren.putIfAbsent(
        seg,
        () => TrieNode(type: TrieNodeType.static, segment: seg),
      );
      child.insert(segments, index + 1, target);
    }
  }

  /// Search for a matching route within the Radix Tree.
  TrieSearchResult? search(
    List<String> segments,
    int index,
    Map<String, String> params,
  ) {
    if (index == segments.length) {
      if (target != null) {
        return TrieSearchResult(target!, params);
      }
      if (catchAllChild?.target != null) {
        final newParams = Map<String, String>.from(params);
        if (catchAllChild!.paramName != null) {
          newParams[catchAllChild!.paramName!] = '';
        }
        return TrieSearchResult(catchAllChild!.target!, newParams);
      }
      return null;
    }

    final seg = segments[index];

    // 1. Static child has highest priority
    final staticChild = staticChildren[seg];
    if (staticChild != null) {
      final res = staticChild.search(segments, index + 1, params);
      if (res != null) return res;
    }

    // 2. Param child (:id)
    if (paramChild != null) {
      final pName = paramChild!.paramName;
      final newParams = Map<String, String>.from(params);
      if (pName != null) {
        newParams[pName] = seg;
      }
      final res = paramChild!.search(segments, index + 1, newParams);
      if (res != null) return res;
    }

    // 3. Catch-all child (*filepath) matches all remaining segments
    if (catchAllChild != null && catchAllChild!.target != null) {
      final pName = catchAllChild!.paramName;
      final newParams = Map<String, String>.from(params);
      if (pName != null) {
        newParams[pName] = segments.sublist(index).join('/');
      }
      return TrieSearchResult(catchAllChild!.target!, newParams);
    }

    return null;
  }
}

/// Radix Tree Router organizing routes by HTTP Method.
class RadixTreeRouter {
  final Map<HttpMethod, TrieNode> _roots = {};

  RadixTreeRouter() {
    for (final method in HttpMethod.values) {
      _roots[method] = TrieNode();
    }
  }

  void insert(HttpMethod method, String path, RouteTarget target) {
    final segments = _splitPath(path);
    _roots[method]!.insert(segments, 0, target);
  }

  TrieSearchResult? search(HttpMethod method, String path) {
    final root = _roots[method];
    if (root == null) return null;

    final segments = _splitPath(path);
    return root.search(segments, 0, <String, String>{});
  }

  List<String> _splitPath(String path) {
    if (path.isEmpty || path == '/') return const [];
    return path.split('/').where((s) => s.isNotEmpty).toList();
  }
}
