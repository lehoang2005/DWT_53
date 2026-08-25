# Generated reference vectors

Do not hand-edit this directory. From the golden-model root run:

```matlab
generate_reference_vectors_1d;
generate_reference_vectors([], false, '');
```

The generators create `1d/` and `2d/` below this directory. Full-size 1280×720
generation is opt-in with `generate_reference_vectors([], true, '')`.

No pre-generated vectors are shipped in the source package: they must be
generated against the exact golden-model revision whose fingerprints are then
recorded in each set's `reference_manifest.txt`.
