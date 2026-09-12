Look only at whether this change is tested.

- a new branch, path or error case with no test
- a test that asserts the implementation (that a function was called) instead of
  the rule (what the caller gets)
- a test that would still pass with the code wrong: no assertion, a mock that
  answers for the thing under test, a fixture that dodges the case
- a test named after a function instead of the behaviour it fixes

If this area of the repo has no tests at all, say so once and approve: that is a
decision someone made, not this change's fault.
