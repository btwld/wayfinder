# Flutter knowledge retrieval fixture

40 questions over the real Markdown of
[`examples/flutter-knowledge`](../../../../examples/flutter-knowledge/knowledge):
9 concept documents and 19 passages (the indexes and the log hold no
passages). Each question is judged against one passage by path plus a literal
fragment of that passage, not against a whole file.

Most questions are paraphrases that avoid the passage's own key terms, because
the 160-question fixture's exact and history groups no longer separate
retrieval methods. Groups:

| Group | Count | What it tests |
| --- | --- | --- |
| `paraphrase` | 30 | The question uses different words from the passage. |
| `scope` | 5 | The passage limits a claim; the question asks about its reach. |
| `exact` | 4 | The question names an API, a version or an error message. |
| `comparison` | 1 | The question relates two concepts. |

The first 20 questions are `development`, the last 20 `held_out`. Both splits
cover every concept. The questions were written before any model ranked them,
and nothing was tuned on the results.

Limitations: the corpus is small, so a random ranking already finds a passage
in the top 5 about a quarter of the time; the questions were written by one author; and each question credits a
single passage even where a neighbouring passage partly answers it.

Run from `packages/wayfinder_embeddings` with a prepared model:

```bash
dart run tool/evaluate_okf_retrieval.dart --no-timing \
  --fixture=fixtures/flutter_retrieval \
  --bundle=../../examples/flutter-knowledge/knowledge \
  --split=development,held_out \
  --output=flutter-retrieval.json
```
