# Mock API

This folder will contain the backend service that exposes a frontend-compatible subset of the 1inch APIs.

Primary docs:
- `API_CONTRACT.md`: frozen frontend-facing request and response contract for the supported subset
- `IMPLEMENTATION_PLAN.md`: execution order and design notes for building the backend
- `FRONTEND_HANDOFF.md`: concrete FE integration brief for the separate frontend repository

Planned responsibilities:
- Mock `Spot Price API` responses for Sepolia using fixed rates
- Mock `Classic Swap v6.1` quote and swap responses for Sepolia
- Proxy the same endpoints to real 1inch in production mode
- Translate between 1inch native-token conventions and this repo's internal conventions when needed

Intended endpoint subset:
- `GET /price/v1.1/:chainId/:addresses`
- `POST /price/v1.1/:chainId`
- `GET /swap/v6.1/:chainId/quote`
- `GET /swap/v6.1/:chainId/swap`
- `GET /swap/v6.1/:chainId/approve/allowance`
- `GET /swap/v6.1/:chainId/approve/transaction`

Runtime baseline:
- Node.js 20+
- Yarn 1.22+

Current scaffold:
- Express + TypeScript service in `src/`
- `GET /healthz` for local runtime checks
- Mock-mode implementations for the frozen Spot Price, Quote, Swap, and approve helper routes
- Production-mode pass-through for the same routes using server-side 1inch auth

Quick start:
- copy `.env.example` to `.env`
- deploy mock tokens with `script/DeployMocksAndMint.s.sol`
- deploy the mock swap separately with `script/DeployMockSwap.s.sol`
- fill the mock token addresses from the token deploy output and `MOCK_SWAP_ADDRESS` from the swap deploy output
- run `yarn install`
- run `yarn dev`

Local deployment flow:
1. Deploy the mock tokens:

	```bash
	forge script script/DeployMocksAndMint.s.sol:DeployMocksAndMint \
	  --rpc-url "$SEPOLIA_RPC_URL" --broadcast
	```

2. Export the deployed token addresses and deploy the mock swap:

	```bash
	export MOCK_TOKEN_MERC20=0x...
	export MOCK_TOKEN_MUSDC=0x...
	export MOCK_TOKEN_MWBTC=0x...
	export MOCK_TOKEN_MEURS=0x...
	export MOCK_TOKEN_MUSDT=0x...

	forge script script/DeployMockSwap.s.sol:DeployMockSwap \
	  --rpc-url "$SEPOLIA_RPC_URL" --broadcast
	```

3. Copy `.env.example` to `.env` and fill in:
	- `MOCK_RPC_URL`
	- `MOCK_SWAP_ADDRESS`
	- `MOCK_TOKEN_MERC20`
	- `MOCK_TOKEN_MUSDC`
	- `MOCK_TOKEN_MWBTC`
	- `MOCK_TOKEN_MEURS`
	- `MOCK_TOKEN_MUSDT`

4. Install and start the backend:

	```bash
	yarn install
	yarn dev
	```

5. Verify the local process:

	```bash
	curl http://127.0.0.1:3000/healthz
	```

The app loads `.env` automatically at runtime.

Deployment target options:
- local dev with `yarn dev`
- production deployment on an existing IONOS-managed Node/VPS environment

Docker deployment:
1. Build the image:

	```bash
	docker build -t ideation-market-mock-api ./mock-api
	```

2. Run it with the backend env file:

	```bash
	docker run --rm \
	  --env-file mock-api/.env \
	  -p 3000:3000 \
	  ideation-market-mock-api
	```

3. Verify the containerized service:

	```bash
	curl http://127.0.0.1:3000/healthz
	```

Notes:
- Do not bake secrets into the image.
- Provide runtime configuration through environment variables or the deployment platform's secret mechanism.
- The Docker image is now the expected production packaging format for the IONOS deployment path.
