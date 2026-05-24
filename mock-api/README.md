# Mock API

This folder will contain the backend service that exposes a frontend-compatible subset of the 1inch APIs.

Primary docs:
- `API_CONTRACT.md`: frozen frontend-facing request and response contract for the supported subset
- `IMPLEMENTATION_PLAN.md`: execution order and design notes for building the backend

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

Deployment target options:
- local dev with `yarn dev`
- production deployment on an existing IONOS-managed Node/VPS environment
