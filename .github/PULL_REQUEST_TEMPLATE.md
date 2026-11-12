## Summary

<!-- What changes, and why. Link the issue or the plan phase if there is one. -->

## Checklist

- [ ] `make check` passes (tests, self-host check, and lint)
- [ ] `changelog.md` updated for user-visible changes
- [ ] Docs updated (`README.md`, `format.md`, `fnlfmt.1`) when flags or
      options change
- [ ] Default behavior stays byte-for-byte compatible with upstream, or the
      intentional change is explained in the summary above
- [ ] New behavior is covered by a test fixture under `tests/` (or a new
      config matrix fixture once that harness exists)
