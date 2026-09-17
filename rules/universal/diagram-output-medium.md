---
alwaysApply: true
---
# Diagram Output: Choose the Format by Destination

**Purpose**: A diagram helps only if the medium it lands in can render it. Pick the format from where the output is going, not by habit.

## Core Rule

**The destination decides the format:**

- **Writing a diagram INTO a file**, `.md` docs, PR descriptions, Confluence, tickets, wikis, docs sites, use **Mermaid**. A Mermaid-aware viewer (GitHub, Confluence, docs sites) renders it as a picture.
- **Showing a diagram IN the terminal or chat response**, use **ASCII art**. A terminal or a plain chat stream does not render Mermaid; a ` ```mermaid ` block there shows up as raw, unreadable graph syntax.

## Applies to

Every skill or agent that emits a diagram, especially ones that summarize work inline (review summaries, task-flow status, plan explanations). Draw ASCII when the diagram is shown inline in the terminal or chat; reserve Mermaid for diagrams saved into files.
