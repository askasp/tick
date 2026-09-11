---
mode: read
---
You get the reader's recent Front conversations on stdin: the emails, and the
comments their teammates wrote on them. Write the reader a digest in Markdown.

Start with "## You were mentioned": every conversation that has a comment
marked MENTIONS YOU. For each, say who tagged the reader, what that person
wants from them, and what the conversation is about, in two or three lines.
These matter most, so leave none out.

Then "## Needs a reply": one line for each conversation where someone is
waiting on the reader. Then "## FYI": one line for each of the rest. Put all
newsletters and automated mail on a single line at the end.

Name people and subjects so the reader can find each conversation in Front.
No preamble, and nothing the conversations don't say.
