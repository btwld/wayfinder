import 'package:ack/ack.dart';

import 'graph.dart';

/// The graph query a host tool accepts, as JSON: optional `types`,
/// `path_prefixes` and `resolutions`, the arguments of
/// [projectWayfinderGraph].
final wayfinderGraphInput = Ack.object({
  'types': Ack.list(Ack.string().minLength(1)).unique().optional(),
  'path_prefixes': Ack.list(Ack.string().minLength(1)).unique().optional(),
  'resolutions': Ack.list(
    Ack.enumString(wayfinderGraphResolutions()),
  ).unique().optional(),
});
