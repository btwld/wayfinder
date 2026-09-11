import 'package:knowledge_embeddings/knowledge_embeddings.dart';

/// Experimental artifacts only; the production default remains Arctic XS.
///
/// Both upstream model cards specify CLS pooling, normalized 384-dimensional
/// vectors, a 512-token context and the same query-only retrieval instruction:
/// https://huggingface.co/Snowflake/snowflake-arctic-embed-s
/// https://huggingface.co/BAAI/bge-small-en-v1.5
const benchmarkModels = <String, EmbeddingModelSpec>{
  'arctic-embed-xs-q8_0': localEmbeddingModel,
  'arctic-embed-s-q8_0': EmbeddingModelSpec(
    id: 'arctic-embed-s-q8_0',
    url:
        'https://huggingface.co/mradermacher/snowflake-arctic-embed-s-GGUF/'
        'resolve/212aceb754d83530ea0e51cb94318d4157c31488/'
        'snowflake-arctic-embed-s.Q8_0.gguf',
    sha256: '49f8b34a1179b38bb92514b43cec2cc86e41bab495b1ef0ffbdc2579c513cbdb',
    bytes: 36685536,
    dimensions: 384,
    maxTokens: 512,
    queryPrefix: 'Represent this sentence for searching relevant passages: ',
    license: 'Apache-2.0',
  ),
  'arctic-embed-s-q4_k_m': EmbeddingModelSpec(
    id: 'arctic-embed-s-q4_k_m',
    url:
        'https://huggingface.co/mradermacher/snowflake-arctic-embed-s-GGUF/'
        'resolve/212aceb754d83530ea0e51cb94318d4157c31488/'
        'snowflake-arctic-embed-s.Q4_K_M.gguf',
    sha256: 'abc6391ca1b2894f066e58bf43385d726247ae874d40e6e67ef9e55ccb25e185',
    bytes: 29082336,
    dimensions: 384,
    maxTokens: 512,
    queryPrefix: 'Represent this sentence for searching relevant passages: ',
    license: 'Apache-2.0',
  ),
  'bge-small-en-v1.5-q8_0': EmbeddingModelSpec(
    id: 'bge-small-en-v1.5-q8_0',
    url:
        'https://huggingface.co/CompendiumLabs/bge-small-en-v1.5-gguf/'
        'resolve/d32f8c040ea3b516330eeb75b72bcc2d3a780ab7/'
        'bge-small-en-v1.5-q8_0.gguf',
    sha256: 'ec38e8da142596baa913124ae50550de284b6916bf59577ef2f0cb9660c2f514',
    bytes: 36806944,
    dimensions: 384,
    maxTokens: 512,
    queryPrefix: 'Represent this sentence for searching relevant passages: ',
    license: 'MIT',
  ),
  'bge-small-en-v1.5-q4_k_m': EmbeddingModelSpec(
    id: 'bge-small-en-v1.5-q4_k_m',
    url:
        'https://huggingface.co/CompendiumLabs/bge-small-en-v1.5-gguf/'
        'resolve/d32f8c040ea3b516330eeb75b72bcc2d3a780ab7/'
        'bge-small-en-v1.5-q4_k_m.gguf',
    sha256: '363a0a4855dff6c653e06efe3209157debcf7f74e52d0d7c71e2747cd523043e',
    bytes: 24808576,
    dimensions: 384,
    maxTokens: 512,
    queryPrefix: 'Represent this sentence for searching relevant passages: ',
    license: 'MIT',
  ),
};
