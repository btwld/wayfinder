# Model-free versus semantic retrieval fixture

100 synthetic, generic OKF concepts form 140 passages. The 160 questions cover
20 topics: ten topics for development and ten different topics for testing.
Each topic supplies six answerable questions and two deliberately unanswerable
ones. Source text, questions, topic assignment, and settings were frozen before
retrieval. All existing regression fixtures remain unchanged.

`manifest.json` records source/query hashes and the shared contextual passage
identity. The actual model tokenizer verified every passage fits its budget
before isolated model-free measurements. No model is required to parse this
fixture or reproduce the passage identity.

These are authored synthetic questions with repeated templates, not independent
human annotations. Topic separation reduces near-duplicate leakage but does not
make the set representative of real projects. Support judgments are path plus
literal passage fragment. In post-run review, `payments-prohibition` revealed an
annotation limitation: the positive instruction to reuse the original key also
supports rejecting a different key, but the frozen judgment only credits the
explicit prohibition paragraph. Reported scores retain that judgment rather
than changing expectations after observing rankings. Do not interpret every
judged miss as an unsupported or incorrect passage.

No client data, new profile fields, or universal authority ordering is encoded.
The explicit governing map is a consumer policy for this synthetic scenario.
See [the results](../../../../docs/wayfinder_embeddings_comparison.md) and
[the benchmark plan](../../../../docs/wayfinder_embeddings_benchmark_plan.md).
