# ObjectBox store written by 0.2.0

`wayfinder_embeddings` 0.2.0 (tag `wayfinder_embeddings-v0.2.0`, commit
`53ecb10`) wrote this store with Dart `objectbox` 5.0.4 and the native 5.3.2
library on macOS arm64. `objectbox_store_test.dart` copies it to a temporary
directory, opens it with the current release, checks every chunk and
embedding, searches it, writes to it and reopens it. Never open the files here
in place.

The data is synthetic and comes from
[`../../support/objectbox_0_2_0_fixture.dart`](../../support/objectbox_0_2_0_fixture.dart),
which the test also imports. The directory holds `data.mdb` and both schema
markers that 0.2.0 writes; ObjectBox recreates `lock.mdb`.

| File | SHA-256 |
| --- | --- |
| `data.mdb` | `3f7a3a91182cf728f69a083367e8e8de46b745f9e17266438fc8c9ec9e969713` |
| `wayfinder_embeddings.schema` | `093d5145dff0cc55fade37b160ce51b8ca4b31a95365fb3453d78bc7f83e2332` |
| `knowledge_embeddings.schema` | `093d5145dff0cc55fade37b160ce51b8ca4b31a95365fb3453d78bc7f83e2332` |

To write it again, run the 0.2.0 code from a throwaway worktree. From the
repository root:

```sh
git worktree add --detach ../wayfinder-0.2.0 wayfinder_embeddings-v0.2.0
cp packages/wayfinder_embeddings/test/support/objectbox_0_2_0_fixture.dart \
  ../wayfinder-0.2.0/packages/wayfinder_embeddings/test/support/
cd ../wayfinder-0.2.0
dart pub get
dart run melos run objectbox:install
cd packages/wayfinder_embeddings
dart run test/support/objectbox_0_2_0_fixture.dart "$TMPDIR/objectbox-0.2.0"
```

Then copy `data.mdb` and the two `.schema` files from that directory here, and
remove the worktree. Each run writes a few different bytes, so a new
`data.mdb` will not match the checksum above; the test checks its contents.
