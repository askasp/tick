Look only at data: what is queried, stored and sent.

- a query inside a loop where one round trip would do
- a new WHERE, ORDER BY or JOIN with no index behind it
- a read with no limit on a table that grows, or every column fetched for two
- a transaction held open across a network call, or a lock held across work
- a migration that rewrites a big table, adds NOT NULL without a default, or
  backfills in one statement
- a response that grows with the data and has no page

Say what happens at a thousand times today's rows. If it is the same, approve.
