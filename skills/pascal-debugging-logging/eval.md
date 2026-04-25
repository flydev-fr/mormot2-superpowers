```yaml
positive:
  - prompt: "Set up TSynLog with stack-trace logging on errors"
    expected: pascal-debugging-logging
  - prompt: "Read this FastMM4 leak report and identify the leak source"
    expected: pascal-debugging-logging
  - prompt: "Resolve a raw address from a stack trace to a source line in our FPC build"
    expected: pascal-debugging-logging
  - prompt: "Enable performance tracing on the order processing service"
    expected: pascal-debugging-logging

negative:
  - prompt: "Write a failing TSynTestCase test for the discount calculator"
    must_not_trigger: pascal-debugging-logging
    expected: test-driven-development
  - prompt: "Walk me through 4-phase root-cause analysis on this REST 500"
    must_not_trigger: pascal-debugging-logging
    expected: systematic-debugging
```
