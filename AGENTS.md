Write collection code as direct pipelines using enumerable interface instead of for-loops, I want my code to feel smalltalk-y rather than look like C code

In general, optimize for readability at the callsite: choose the shortest expression that is still explicit about behavior, and avoid defensive noise unless there is a real failure mode to handle.

Prefer failing loudly over defensive guards when missing inputs or files are programmer/configuration errors rather than recoverable runtime cases.

All changes should be as surgical as possible; always aim for the smallest diff possible, never add ceremony or overhead, reuse what you can reuse

When implementing, optimize for first-pass acceptance: make the smallest possible change that fully solves the request, and stop. Do not add side refactors, optional architecture cleanup, or “future-proof” abstractions unless explicitly asked.

Write for call-site readability first. Keep logic where it is used if extraction would hide behavior. Inline one-use variables and one-use helpers. Prefer direct, compact flow that reads like a short summary of intent.

Set a high bar for abstraction. Add a new method/class only if it removes real duplication or materially improves clarity. Do not introduce constants for readable string literals. Avoid ceremony, indirection, and defensive scaffolding when failure is a programmer/configuration error.

Use verb-first method names with concrete intent (`mark_as_stale`, `find_image_paths_by_username`, `save_download`). Prefer short names that describe behavior, not mechanism. Keep each method at one level of abstraction.

For collection logic, use enumerable pipelines (`map`, `select`, `reject`, `group_by`, `transform_values`, `flat_map`) instead of index-based loops. Prefer concise Smalltalk-collections style over C-like iteration patterns.

Prefer plain `each` with explicit accumulators over `each_with_object`; the explicit locals are usually easier to scan at a glance.

For fixed key dispatch/validation, prefer `case` over membership checks on string arrays when mapping allowed keys to behavior.

Avoid unnecessary coercion like `to_s`; keep original value types unless a concrete boundary requires conversion.

Follow surrounding project conventions exactly (especially CLI/style patterns like `options_by_example`) instead of introducing new frameworks or styles. If existing code is “not by the book,” match it unless explicitly asked to redesign.

Before finalizing any change, self-review the diff and reject your own patch if any of these are true
- introduced unnecessary helpers
- added constants for readable strings
- added defensive checks without a real failure mode
- changed unrelated code
- used index-style loops where enumerable pipelines fit
- method names are not verb-first
- call site became less readable.
