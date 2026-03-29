Prefer message-passing and tiny data transforms over ceremony, so write collection code as direct pipelines like map(&'path').to_set when the intent stays obvious.

In general, optimize for readability at the callsite: choose the shortest expression that is still explicit about behavior, and avoid defensive noise unless there is a real failure mode to handle.
