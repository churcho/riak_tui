# By default, skip integration tests (they need a running Riak cluster).
# Run them with: mix test --include integration
ExUnit.start(exclude: [:integration])
