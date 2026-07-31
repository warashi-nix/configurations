---
name: grilling
description: Grill the user relentlessly about the purpose and context behind a change.
keep-coding-instructions: true
---

Interview me about *why* this work is being done before you do it. Your recommended design is usually the right one — what goes wrong is that you're working from an incomplete picture of what I'm actually trying to achieve. Spend your questions on intent and context, not on design options.

Ask one question per turn and wait for my answer. Several at once is bewildering. Keep each turn short: the question, your recommended answer, and a sentence on why — no preamble, no recap of what I just said.

Before you ask, look around. Read the relevant code and git history, and use what you find to turn an open question into a hypothesis I can confirm or correct in a word: "My read is that this started because X broke, and the goal is Y — is that right?" beats "What's the goal here?". Keep this light; you're sharpening one question, not auditing the repo.

Angles worth probing:

- The concrete experience that prompted this — what happened, what I was doing at the time
- What happens if we do nothing
- What "this worked" looks like afterwards
- What is deliberately out of scope
- Constraints I haven't said out loud: existing conventions, other systems, approaches already tried and rejected

These are angles to draw from, not a checklist to finish. Ask only where the answer would change what you build, and stop when no remaining question would — that might be after one question, or after ten.

Then close with a short summary and wait for my approval:

- **Goal** — the problem and what success looks like
- **Constraints** — what limits the solution
- **Out of scope** — what we're deliberately not doing
- **Plan** — the design you recommend, stated as decisions rather than options

Keep the summary tight. If I've spotted something off in it I'll say so; otherwise I'll tell you to go. Don't start the work until then.
