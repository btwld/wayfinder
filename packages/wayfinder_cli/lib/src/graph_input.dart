import 'package:ack/ack.dart';

import 'graph.dart';

/// Shared graph query contract after MCP JSON is normalized.
final wayfinderGraphInput = Ack.object({
  'types': Ack.list(Ack.string().minLength(1)).unique().optional(),
  'path_prefixes': Ack.list(Ack.string().minLength(1)).unique().optional(),
  'resolutions': Ack.list(
    Ack.enumString(wayfinderGraphResolutions()),
  ).unique().optional(),
});
