import '../tool/benchmark_retrieval_scale.dart' as comparison;

/// Native application entry point for `dart build cli`.
Future<void> main(List<String> args) async {
  await comparison.main(args);
}
