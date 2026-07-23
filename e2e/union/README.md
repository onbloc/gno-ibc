# Union E2E

```sh
cd e2e/union
install -m 600 .env.example .env
# Fill in .env before running.

./run-channel-e2e.sh
./run-channel-e2e.sh --apply
./run-channel-e2e.sh --resume
./run-channel-e2e.sh --resume --apply
./run-channel-e2e.sh --resume --apply --erc20-to-gno
```
