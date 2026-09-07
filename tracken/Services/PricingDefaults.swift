// Offline starting prices from the official standard tables, verified 2026-09-07.
// Updated catalogs are cached separately; see PricingCatalog.source(for:).
nonisolated enum PricingDefaults {
    static let openAI = """
    ### Standard pricing data
    | Model | Short context input | Short context cached input | Short context cache writes | Short context output | Long context input | Long context cached input | Long context cache writes | Long context output |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | gpt-6-astra | $10.00 | $1.00 | $12.50 | $50.00 | $20.00 | $2.00 | $25.00 | $75.00 |
    | gpt-5.6-sol | $4.00 | $0.40 | $5.00 | $20.00 | $8.00 | $0.80 | $10.00 | $30.00 |
    | gpt-5.6-terra | $2.00 | $0.20 | $2.50 | $12.00 | $4.00 | $0.40 | $5.00 | $18.00 |
    | gpt-5.6-luna | $0.20 | $0.02 | $0.25 | $1.20 | $0.40 | $0.04 | $0.50 | $1.80 |
    | gpt-5.5 (<272K context length) | $5.00 | $0.50 | - | $30.00 | $10.00 | $1.00 | - | $45.00 |
    | gpt-5.5-pro (<272K context length) | $30.00 | - | - | $180.00 | $60.00 | - | - | $270.00 |
    | gpt-5.4 (<272K context length) | $2.50 | $0.25 | - | $15.00 | $5.00 | $0.50 | - | $22.50 |
    | gpt-5.4-mini | $0.75 | $0.075 | - | $4.50 | - | - | - | - |
    | gpt-5.4-nano | $0.20 | $0.02 | - | $1.25 | - | - | - | - |
    | gpt-5.4-pro (<272K context length) | $30.00 | - | - | $180.00 | $60.00 | - | - | $270.00 |
    | gpt-5.2 | $1.75 | $0.175 | - | $14.00 | - | - | - | - |
    | gpt-5.2-pro | $21.00 | - | - | $168.00 | - | - | - | - |
    | gpt-5.1 | $1.25 | $0.125 | - | $10.00 | - | - | - | - |
    | gpt-5 | $1.25 | $0.125 | - | $10.00 | - | - | - | - |
    | gpt-5-mini | $0.25 | $0.025 | - | $2.00 | - | - | - | - |
    | gpt-5-nano | $0.05 | $0.005 | - | $0.40 | - | - | - | - |
    | gpt-5-pro | $15.00 | - | - | $120.00 | - | - | - | - |
    | gpt-4.1 | $2.00 | $0.50 | - | $8.00 | - | - | - | - |
    | gpt-4.1-mini | $0.40 | $0.10 | - | $1.60 | - | - | - | - |
    | gpt-4.1-nano | $0.10 | $0.025 | - | $0.40 | - | - | - | - |
    | gpt-4o | $2.50 | $1.25 | - | $10.00 | - | - | - | - |
    | gpt-4o-2024-05-13 | $5.00 | - | - | $15.00 | - | - | - | - |
    | gpt-4o-mini | $0.15 | $0.075 | - | $0.60 | - | - | - | - |
    | o1 | $15.00 | $7.50 | - | $60.00 | - | - | - | - |
    | o1-pro | $150.00 | - | - | $600.00 | - | - | - | - |
    | o3-pro | $20.00 | - | - | $80.00 | - | - | - | - |
    | o3 | $2.00 | $0.50 | - | $8.00 | - | - | - | - |
    | o4-mini | $1.10 | $0.275 | - | $4.40 | - | - | - | - |
    | o3-mini | $1.10 | $0.55 | - | $4.40 | - | - | - | - |
    | gpt-4-turbo-2024-04-09 | $10.00 | - | - | $30.00 | - | - | - | - |
    | gpt-4-0613 | $30.00 | - | - | $60.00 | - | - | - | - |
    | gpt-3.5-turbo | $0.50 | - | - | $1.50 | - | - | - | - |
    | gpt-3.5-turbo-0125 | $0.50 | - | - | $1.50 | - | - | - | - |
    | gpt-3.5-turbo-1106 | $1.00 | - | - | $2.00 | - | - | - | - |
    | gpt-3.5-turbo-instruct | $1.50 | - | - | $2.00 | - | - | - | - |
    | davinci-002 | $2.00 | - | - | $2.00 | - | - | - | - |
    | babbage-002 | $0.40 | - | - | $0.40 | - | - | - | - |
    """

    static let claude = """
    ## Model pricing
    | Model | Base input tokens | 5m cache writes | 1h cache writes | Cache hits and refreshes | Output tokens |
    | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------- | --------------- | --------------- | ------------------------ | ------------- |
    | Claude Fable 5.1 | $10 / MTok | $12.50 / MTok | $20 / MTok | $0.25 / MTok1 | $50 / MTok |
    | Claude Mythos 5.1 ([limited availability](https://anthropic.com/glasswing)) | $10 / MTok | $12.50 / MTok | $20 / MTok | $0.25 / MTok1 | $50 / MTok |
    | Claude Fable 5 | $10 / MTok | $12.50 / MTok | $20 / MTok | $1 / MTok | $50 / MTok |
    | Claude Mythos 5 ([limited availability](https://anthropic.com/glasswing)) | $10 / MTok | $12.50 / MTok | $20 / MTok | $1 / MTok | $50 / MTok |
    | Claude Opus 5 | $5 / MTok | $6.25 / MTok | $10 / MTok | $0.50 / MTok | $25 / MTok |
    | Claude Opus 4.8 | $5 / MTok | $6.25 / MTok | $10 / MTok | $0.50 / MTok | $25 / MTok |
    | Claude Opus 4.7 | $5 / MTok | $6.25 / MTok | $10 / MTok | $0.50 / MTok | $25 / MTok |
    | Claude Opus 4.6 | $5 / MTok | $6.25 / MTok | $10 / MTok | $0.50 / MTok | $25 / MTok |
    | Claude Opus 4.5 | $5 / MTok | $6.25 / MTok | $10 / MTok | $0.50 / MTok | $25 / MTok |
    | Claude Opus 4.1 ([retired, except on Bedrock and Google Cloud](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $15 / MTok | $18.75 / MTok | $30 / MTok | $1.50 / MTok | $75 / MTok |
    | Claude Opus 4 ([retired, except on Google Cloud](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $15 / MTok | $18.75 / MTok | $30 / MTok | $1.50 / MTok | $75 / MTok |
    | Claude Sonnet 5 | $2 / MTok | $2.50 / MTok | $4 / MTok | $0.20 / MTok | $10 / MTok |
    | Claude Sonnet 4.6 | $3 / MTok | $3.75 / MTok | $6 / MTok | $0.30 / MTok | $15 / MTok |
    | Claude Sonnet 4.5 | $3 / MTok | $3.75 / MTok | $6 / MTok | $0.30 / MTok | $15 / MTok |
    | Claude Sonnet 4 ([retired, except on Bedrock and Google Cloud](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $3 / MTok | $3.75 / MTok | $6 / MTok | $0.30 / MTok | $15 / MTok |
    | Claude Haiku 4.5 | $1 / MTok | $1.25 / MTok | $2 / MTok | $0.10 / MTok | $5 / MTok |
    | Claude Haiku 3.5 ([retired, except on Bedrock and Google Cloud](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $0.80 / MTok | $1 / MTok | $1.60 / MTok | $0.08 / MTok | $4 / MTok |
    """
}
