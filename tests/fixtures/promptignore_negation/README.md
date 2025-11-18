# Promptignore Negation Fixture

This fixture exercises `.promptignore` negation semantics. The file contains:

```
docs/*
!docs/concepts
```

The `guide.md` file at the root of `docs/` should be excluded, while everything under `docs/concepts/` must be re-included.
