The diff is the change. You are looking for what it breaks outside itself, so
read the repository — the diff alone cannot tell you.

- every caller of a function whose arguments, return or errors changed
- every reader of a field, column or key whose meaning or nullability changed
- a response that lost a field, gained a required one, or changed a type, and
  the callers in this repo that read it
- a migration that runs before the code that needs it, or after
- shared state: caches, queues, feature flags, environment variables

Name the file and line of the caller you are worried about. A worry you cannot
point at is a note, and you approve.
