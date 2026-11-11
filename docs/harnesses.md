# Harnesses

Claude Code, Codex, and OpenCode are **harnesses**: they run models and manage agent sessions and tools. Anthropic and OpenAI are **model providers**. Alveary's settings show whether each harness is installed and let you turn each one on or off.

## Claude models

Claude model pickers offer Fable 5.2 (`claude-fable-5-2`), Opus 5.5 (`claude-opus-5-5`), Sonnet 5.5 (`claude-sonnet-5-5`, the default), and Haiku 5.5 (`claude-haiku-5-5`). The `fable`, `opus`, `sonnet`, and `haiku` shorthands select them, while a saved model ID keeps its version. All four support Low through Max effort, and an effort a model doesn't support falls back to its default: High for Fable 5.2, Medium for the others.

## OpenCode

Alveary targets OpenCode 1.18.31's stable V1 server protocol and needs a compatible stable `1.x` CLI. It supports coding and review sessions, approvals, steering, subagents, compaction, and images where the model takes them. Read-only utility and review-team workers need a specific model and a supported provider connection. Goals, fast mode, and sandbox equivalence aren't supported.

[OpenCode harness integration](opencode-harness.md) covers its behavior, limitations, and compatibility testing.
