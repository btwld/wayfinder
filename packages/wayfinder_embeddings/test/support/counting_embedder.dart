import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

class CountingEmbedder extends BaseEmbedder {
  CountingEmbedder({this.focus});
  final String? focus;
  final documents = <String>[];
  bool fail = false;
  @override
  String get sourceName => 'test';
  @override
  String get modelName => 'fixed';
  @override
  int get dimension => 384;
  @override
  Future<List<double>> generateEmbedding(String text) async {
    if (fail) throw StateError('inference failed');
    documents.add(text);
    return focus == null || text.contains(focus!)
        ? [1, ...List<double>.filled(383, 0)]
        : [0, 1, ...List<double>.filled(382, 0)];
  }

  @override
  Future<List<double>> generateQueryVector(String text) async => [
    1,
    ...List<double>.filled(383, 0),
  ];
}
