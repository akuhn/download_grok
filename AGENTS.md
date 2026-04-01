Write collection code as direct pipelines using enumerable interface instead of for-loops, I want my code to feel smalltalk-y rather than look like C code

In general, optimize for readability at the callsite: choose the shortest expression that is still explicit about behavior, and avoid defensive noise unless there is a real failure mode to handle.

Prefer failing loudly over defensive guards when missing inputs or files are programmer/configuration errors rather than recoverable runtime cases.

All changes should be as surgical as possible; always aim for the smallest diff possible, never add ceremony or overhead, reuse what you can reuse
