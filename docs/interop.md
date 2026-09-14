# glTF documents carrying EXT_meshopt_compression

zmeshopt binds one upstream library and handles no file format. A glTF
document that uses `EXT_meshopt_compression` needs a parser to read the buffer
views and this package to decode them.

The sibling package `zcgltf` covers the parsing half. Its README documents the
pairing contract — which decoder each buffer view maps to, and in what order —
and its `tests/interop/` package runs the two together end to end, in its own
CI, against a released zmeshopt.
