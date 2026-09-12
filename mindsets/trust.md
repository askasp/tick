Look only at what could be abused or leaked.

- a route, query or job that never checks who is asking, or checks the wrong
  thing: another tenant's id, a role that isn't enough
- input that reaches a query, a shell, a path or a URL unchecked
- a secret, token or key in the code, a log line or a response
- personal or health data in a log, an error message, an analytics event or a
  call to somebody else's service
- something that used to be private and is returned now

Say who could see or do what they shouldn't, and how they would. If you cannot
say how, it is a note, and you approve.
