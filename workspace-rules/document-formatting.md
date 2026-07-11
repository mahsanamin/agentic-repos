# Document Formatting Rules

Universal formatting conventions for any document an AI writes inside a project, PR descriptions, ticket descriptions, weekly reports, internal docs, RFCs.

These rules are deliberately small. They exist because AI-generated prose has a recognisable shape (em-dashes everywhere, decorative horizontal rules, padded paragraphs that restate the same point) and the goal is to make documents read like a human wrote them.

## Separators

- **Never use `---` (horizontal rules) inside the body.** They're decorative and break flow when read in management tools that don't render them well. Headers and table boundaries are the structure; you don't need extra dividers.
- **Don't use em dashes (`-`) in body sentences.** Use commas, colons, hyphens with spaces (` - `), or just start a new sentence. Standardised template headers that already use em dashes (e.g., a fixed report header) may keep them, but body prose should not.

## Repetition

- **No restating the same point across sections.** If the same fact appears in Summary AND Approach AND Testing sections, it's a sign the document is padded. State each fact once in the most relevant section; reference rather than re-state.
- **No filler.** Words and phrases like `essentially`, `broadly`, `across the board`, `comprehensive`, `robust`, `seamless`, `delightful`, `it's important to note`, `consider that`, `in order to` are signs of AI-generated prose. Cut them.

## Content discipline

- **Keep claims tied to evidence.** Concrete numbers, dates, names, and decisions need a source in this turn's reading (a file, a PR, a Slack message, a meeting note). If you can't point at the source, soften the claim or drop it.
- **Preserve exact phrasing for direct quotes.** When citing a person's decision or product framing, use their actual words rather than paraphrased versions. Paraphrasing leaks AI voice into someone else's statement.
- **Explain "why" naturally.** When a decision isn't obvious from context, say why in one sentence, not three. Readers should feel a human reasoned through it, not that a parser reconstructed it.

## Structure

- Use headers and tables to organise content. Don't use decorative separators or fixed-width frames.
- One idea per sentence. Three or more comma/and clauses in a row is a robot-prose tell, split into separate sentences or convert to a list.
- Active voice. "We finished X" beats "X was finished".
- Vary sentence length. A short sentence, then a longer one with context, then short again. Uniform paragraph length is another AI tell.

## External-share safety

Documents shared externally (e.g., filenames prefixed `O_FBL_Ext_Share_` or similar project conventions) follow stricter neutrality and audit-safety rules, typically defined in each project's external-document-sharing policy. Refer to the project's policy doc rather than restating the rules here.

When writing externally-shared content:

- Prefer "aligned with", "designed to meet". Avoid "compliant with" unless legally verified.
- Avoid marketing adjectives. Use neutral, audit-safe language only.
