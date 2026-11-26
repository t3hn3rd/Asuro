# test.harness

Every Asuro unit that implements unit tests **must use `test.harness`** to record its assertions. The harness logs failed checks and per-unit totals and includes the results in the aggregate summary used by CI.

## Writing a unit test

Declare `UnitTest` in the unit's interface and add `test.harness` to its implementation `uses` clause. Give each suite a local `TTestContext` and use the same context throughout the test.

```pascal
procedure UnitTest;
var
    context : TTestContext;
begin
    test.harness.Start(@context, 'example.math');
    test.harness.Assert(@context, add(2, 3) = 5, 'add two positive integers');
    test.harness.Finish(@context);
end;
```

- `Start` initialises the context and registers the suite under its full unit name.
- `Assert` counts each check and logs failures immediately. Give each check a name that describes the expected behaviour. Direct `io.syslog` messages leave the assertion counters unchanged.
- `Finish` prints the suite's pass and fail counts and records its overall result. Call it exactly once on every path after `Start`.

Report setup failures with `Assert`, guard checks that depend on successful setup, and release resources before calling `Finish`. The [boot test runner](test.md) handles `Init`, `Print`, and suite registration.
